// =============================================================================
// MNC Physics v3: per-step control of chosen bodies.
//
// The route from a body to its PhysX actor and the PxScene::simulate hook come from the
// Cyberpunk Wind Framework session's reverse engineering of game 2.31 (its
// docs/PHYSICS_RE_FINDINGS.md section 3.5 and plugin/src/PhysXWind.cpp), shared with MNC
// at Omar's request; reimplemented here.
//
//   - Scripts record a wish per body (gravity on/off, a continuous force and torque).
//     Nothing touches PhysX from the script thread.
//   - Before every physics step (PxScene::simulate / collide, chained after anyone else's
//     hook on the same vtable slot), each wish is applied to its actor. The actor is found
//     again every step through the engine's proxy table, read raw: the id's generation
//     must still match, the proxy must be a physical-system proxy, the body index in range,
//     the actor a PxRigidDynamic in this very scene. A body despawned in the meantime is
//     skipped, never touched.
//   - What the actor really does (velocity, spin, its gravity flag) is read back each step.
// =============================================================================
#include "PhysXBody.hpp"

#include <Windows.h>

#include <atomic>
#include <cstring>
#include <cstdio>
#include <string>

#include <PxPhysics.h>
#include <PxRigidDynamic.h>
#include <PxScene.h>
#include <PxSceneLock.h>

using namespace physx;

namespace
{
constexpr std::size_t SLOT_SIMULATE = 56; // PxScene vtable (3.4 order, checked in PhysX3_x64.dll)
constexpr std::size_t SLOT_COLLIDE = 58;
constexpr std::size_t MAX_BODIES = 32;
constexpr ULONGLONG HOLD_MS = 300;

// the engine's physics proxy table (address-library hashes, game 2.31)
constexpr uint32_t HASH_PROXY_MANAGER = 37956006;     // pointer variable
constexpr uint32_t HASH_PHYSICAL_PROXY_VTBL = 4234546548; // physical-system proxy vtable
constexpr std::size_t MGR_PROXIES = 0x2018;           // 16-byte entries, proxy pointer first
constexpr std::size_t MGR_GENERATIONS = 0x102010;     // u16 per index
constexpr std::size_t PROXY_ACTORS = 0x50;            // PxRigidActor** (one per body)
constexpr std::size_t PROXY_COUNT = 0x5C;             // u32 body count

using Simulate_t = bool (*)(PxScene*, PxReal, PxBaseTask*, void*, PxU32, bool);
using Collide_t = void (*)(PxScene*, PxReal, PxBaseTask*, void*, PxU32, bool);
using PxGetPhysics_t = PxPhysics& (*)();

struct Wish
{
    uint32_t proxy;
    uint32_t index;
    ULONGLONG until;   // dropped after this (GetTickCount64)
    int32_t gravity;   // -1 leave as is, 0 off, 1 on
    bool restore;      // put gravity back on when the wish is dropped
    int32_t collide;   // -1 leave as is, 0 its shapes push nothing (queries still hit them), 1 back
    uint32_t turnedOff; // the shapes (bit per shape, first 32) whose simulation flag we cleared
    float force[3];
    float torque[3];
    MNC::PhysXBody::Readback back;
};

RED4ext::v1::PluginHandle g_handle = nullptr;
const RED4ext::v1::Sdk* g_sdk = nullptr;
PxGetPhysics_t g_getPhysics = nullptr;
void** g_vtable = nullptr;
Simulate_t g_simulate = nullptr;
Collide_t g_collide = nullptr;
std::atomic<bool> g_hooked{false};
std::atomic<uint32_t> g_steps{0};

Wish g_wishes[MAX_BODIES] = {};
SRWLOCK g_lock = SRWLOCK_INIT;

// the watchdog's heartbeats (GetTickCount64 ms; 0 = never)
std::atomic<ULONGLONG> g_lastStep{0};
std::atomic<ULONGLONG> g_lastScript{0};
std::atomic<ULONGLONG> g_driveStart{0};
SRWLOCK g_markLock = SRWLOCK_INIT;
char g_mark[192] = "none";

uintptr_t Resolve(uint32_t aHash)
{
    // RED4ext's resolver (0 when the hash is unknown), so a missing address turns the
    // feature off instead of ending the process
    using Resolve_t = uintptr_t (*)(uint32_t);
    static Resolve_t resolve = nullptr;
    if (!resolve)
    {
        auto red4ext = GetModuleHandleW(L"RED4ext.dll");
        if (red4ext)
        {
            resolve = reinterpret_cast<Resolve_t>(GetProcAddress(red4ext, "RED4ext_ResolveAddress"));
        }
    }
    return resolve ? resolve(aHash) : 0;
}

// the actor behind a body, read from the engine's proxy table; nullptr unless every check holds
PxRigidDynamic* ActorOf(uint32_t aProxy, uint32_t aIndex, PxScene* aScene)
{
    static const uintptr_t mgrVar = Resolve(HASH_PROXY_MANAGER);
    static const uintptr_t proxyVtbl = Resolve(HASH_PHYSICAL_PROXY_VTBL);
    if (!mgrVar || !proxyVtbl)
    {
        return nullptr;
    }
    const auto mgr = *reinterpret_cast<const uint8_t* const*>(mgrVar);
    if (!mgr)
    {
        return nullptr;
    }
    const uint32_t slot = aProxy & 0xFFFF;
    const uint16_t gen = static_cast<uint16_t>(aProxy >> 16);
    if (*reinterpret_cast<const uint16_t*>(mgr + MGR_GENERATIONS + slot * 2) != gen)
    {
        return nullptr; // the proxy was released (and maybe reused): not ours any more
    }
    const auto proxy = *reinterpret_cast<const uint8_t* const*>(mgr + MGR_PROXIES + slot * 16);
    if (!proxy || *reinterpret_cast<const uintptr_t*>(proxy) != proxyVtbl)
    {
        return nullptr;
    }
    const auto count = *reinterpret_cast<const uint32_t*>(proxy + PROXY_COUNT);
    const auto actors = *reinterpret_cast<PxRigidActor* const* const*>(proxy + PROXY_ACTORS);
    if (!actors || aIndex >= count || !actors[aIndex])
    {
        return nullptr;
    }
    auto dyn = actors[aIndex]->is<PxRigidDynamic>();
    if (!dyn || dyn->getScene() != aScene)
    {
        return nullptr;
    }
    return dyn;
}

// a body in the simulation (it pushes and is pushed) or not: PxActorFlag::eDISABLE_SIMULATION,
// which PhysX documents for actors kept for scene queries only (bullets and rays still find
// them). Only a body this took out is put back. v3.1's first build changed its shapes'
// flags through PxShape's virtuals, whose slots in the game's PhysX3_x64.dll don't match the
// 3.4 headers: getFlags was another function, and the game crashed reading its result. The
// actor's setActorFlag/getActorFlags slots are the ones the gravity test proved in game.
void SetSimulated(PxRigidDynamic* aActor, Wish& aWish, bool aOn)
{
    const bool out = aActor->getActorFlags().isSet(PxActorFlag::eDISABLE_SIMULATION);
    if (!aOn && !out)
    {
        aActor->setActorFlag(PxActorFlag::eDISABLE_SIMULATION, true);
        aWish.turnedOff = 1;
    }
    else if (aOn && out && aWish.turnedOff)
    {
        aActor->setActorFlag(PxActorFlag::eDISABLE_SIMULATION, false);
        aWish.turnedOff = 0;
    }
}

std::atomic<uint32_t> g_faults{0};

// one wish, one step (no C++ objects needing unwinding: it runs under a structured-exception
// guard, so a fault in here drops the wish instead of taking the game down)
void DriveOne(Wish& w, PxScene* aScene, ULONGLONG aNow)
{
    auto actor = ActorOf(w.proxy, w.index, aScene);
    const bool expired = w.until <= aNow;
    if (!actor)
    {
        if (expired)
        {
            w = {};
        }
        return;
    }
    const bool gravityOff = actor->getActorFlags().isSet(PxActorFlag::eDISABLE_GRAVITY);
    if (expired)
    {
        // the script stopped asking: give the body back as the game had it
        if (w.restore && gravityOff)
        {
            actor->setActorFlag(PxActorFlag::eDISABLE_GRAVITY, false);
            actor->wakeUp();
        }
        if (w.turnedOff)
        {
            SetSimulated(actor, w, true);
        }
        w = {};
        return;
    }
    {
        if (w.collide == 0)
        {
            SetSimulated(actor, w, false);
        }
        else if (w.collide == 1 && w.turnedOff)
        {
            SetSimulated(actor, w, true);
        }
        if (w.gravity >= 0)
        {
            const bool wantOff = w.gravity == 0;
            if (wantOff != gravityOff)
            {
                if (w.back.steps > 0)
                {
                    ++w.back.reset; // someone else set it back since our last step
                }
                actor->setActorFlag(PxActorFlag::eDISABLE_GRAVITY, wantOff);
            }
        }
        const PxVec3 f(w.force[0], w.force[1], w.force[2]);
        const PxVec3 t(w.torque[0], w.torque[1], w.torque[2]);
        if (!f.isZero() || !t.isZero())
        {
            if (!actor->getRigidBodyFlags().isSet(PxRigidBodyFlag::eKINEMATIC))
            {
                actor->addForce(f, PxForceMode::eFORCE, true);
                actor->addTorque(t, PxForceMode::eFORCE, true);
            }
        }
        const auto v = actor->getLinearVelocity();
        const auto s = actor->getAngularVelocity();
        w.back.vel[0] = v.x;
        w.back.vel[1] = v.y;
        w.back.vel[2] = v.z;
        w.back.spin[0] = s.x;
        w.back.spin[1] = s.y;
        w.back.spin[2] = s.z;
        w.back.gravity = actor->getActorFlags().isSet(PxActorFlag::eDISABLE_GRAVITY) ? 0 : 1;
        ++w.back.steps;
    }
}

bool DriveGuarded(Wish* aWish, PxScene* aScene, ULONGLONG aNow)
{
    __try
    {
        DriveOne(*aWish, aScene, aNow);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

void Drive(PxScene* aScene)
{
    g_steps.fetch_add(1, std::memory_order_relaxed);
    const auto now = GetTickCount64();
    g_lastStep.store(now, std::memory_order_relaxed);
    g_driveStart.store(now, std::memory_order_relaxed);
    AcquireSRWLockExclusive(&g_lock);
    for (auto& w : g_wishes)
    {
        if (!w.proxy)
        {
            continue;
        }
        if (!DriveGuarded(&w, aScene, now))
        {
            // a fault on this body: never touch it again (it is dropped, not put back)
            w = {};
            g_faults.fetch_add(1, std::memory_order_relaxed);
        }
    }
    ReleaseSRWLockExclusive(&g_lock);
    g_driveStart.store(0, std::memory_order_relaxed);
}

// ---- the hang watchdog (v3.3) ------------------------------------------------------
void WatchLog(const char* aText)
{
    char dir[MAX_PATH] = {};
    if (!GetEnvironmentVariableA("LOCALAPPDATA", dir, MAX_PATH))
    {
        return;
    }
    std::string folder = std::string(dir) + "\\MNCPhysics";
    CreateDirectoryA(folder.c_str(), nullptr);
    FILE* f = nullptr;
    if (fopen_s(&f, (folder + "\\watchdog.log").c_str(), "a") == 0 && f)
    {
        SYSTEMTIME st;
        GetLocalTime(&st);
        fprintf(f, "[%04u-%02u-%02u %02u:%02u:%02u.%03u] %s\n", st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute,
                st.wSecond, st.wMilliseconds, aText);
        fflush(f);
        fclose(f);
    }
}

DWORD WINAPI WatchThread(LPVOID)
{
    bool scriptStalled = false;
    bool driveStalled = false;
    bool physStalled = false;
    ULONGLONG stallStart = 0;
    WatchLog("watchdog on");
    for (;;)
    {
        Sleep(500);
        const ULONGLONG now = GetTickCount64();
        const ULONGLONG script = g_lastScript.load(std::memory_order_relaxed);
        const ULONGLONG step = g_lastStep.load(std::memory_order_relaxed);
        const ULONGLONG drive = g_driveStart.load(std::memory_order_relaxed);
        char mark[192];
        AcquireSRWLockShared(&g_markLock);
        memcpy(mark, g_mark, sizeof(mark));
        ReleaseSRWLockShared(&g_markLock);
        mark[sizeof(mark) - 1] = 0;
        char line[512];
        // a clean link close marks itself idle: the scripts going quiet then is no stall (a60's
        // first logs reported every disconnect)
        const bool idle = strncmp(mark, "idle", 4) == 0;
        // the game stopped stepping physics while a drone was flown (scripts heard from in
        // the last 10 s): the engine itself stalled
        if (!idle && step && script && now - step > 2000 && now - script < 10000 && !physStalled)
        {
            physStalled = true;
            sprintf_s(line, "STALL: no physics step for %llu ms (the engine stalled); last stage: %s; last MNC script call %llu ms ago",
                      now - step, mark, now - script);
            WatchLog(line);
        }
        else if (physStalled && step && now - step < 1000)
        {
            physStalled = false;
            WatchLog("resumed: physics steps back");
        }
        // scripts were flying a drone (heard from in the last 10 min) and went quiet for 2 s
        if (!idle && script && now - script > 2000 && now - script < 600000 && !scriptStalled)
        {
            scriptStalled = true;
            stallStart = script;
            sprintf_s(line, "STALL: no MNC script call for %llu ms; last stage: %s; last physics step %llu ms ago (%u steps so far); %s",
                      now - script, mark, step ? now - step : 0ULL, g_steps.load(), drive ? "INSIDE our physics step" : "not in our physics step");
            WatchLog(line);
        }
        else if (scriptStalled && now - script < 1000)
        {
            scriptStalled = false;
            sprintf_s(line, "resumed: scripts back after %llu ms", script - stallStart);
            WatchLog(line);
        }
        // our own per-step work running for 2 s: a hang inside it
        if (drive && now - drive > 2000 && !driveStalled)
        {
            driveStalled = true;
            sprintf_s(line, "STALL: inside our physics step for %llu ms; last stage: %s", now - drive, mark);
            WatchLog(line);
        }
        else if (driveStalled && !drive)
        {
            driveStalled = false;
            WatchLog("resumed: our physics step finished");
        }
    }
    return 0;
}

void DriveLocked(PxScene* aScene)
{
    if (aScene->getFlags() & PxSceneFlag::eREQUIRE_RW_LOCK)
    {
        PxSceneWriteLock lock(*aScene, "MNCPhysics");
        Drive(aScene);
    }
    else
    {
        Drive(aScene);
    }
}

bool Simulate_Detour(PxScene* aThis, PxReal aDt, PxBaseTask* aTask, void* aMem, PxU32 aSize, bool aControl)
{
    DriveLocked(aThis);
    return g_simulate(aThis, aDt, aTask, aMem, aSize, aControl);
}

void Collide_Detour(PxScene* aThis, PxReal aDt, PxBaseTask* aTask, void* aMem, PxU32 aSize, bool aControl)
{
    DriveLocked(aThis);
    g_collide(aThis, aDt, aTask, aMem, aSize, aControl);
}

// swaps our detour into a vtable slot, chaining to whatever is there (another plugin's hook
// included). Compare-and-swap against the value just read (the Wind Framework session's
// advice), so two first-time patches can't lose one another. Returns what we replaced.
void* PatchSlot(void** aVtable, std::size_t aSlot, void* aValue)
{
    void* previous = nullptr;
    DWORD old = 0;
    if (VirtualProtect(&aVtable[aSlot], sizeof(void*), PAGE_READWRITE, &old))
    {
        for (int tries = 0; tries < 8; ++tries)
        {
            void* seen = aVtable[aSlot];
            if (InterlockedCompareExchangePointer(&aVtable[aSlot], aValue, seen) == seen)
            {
                previous = seen;
                break;
            }
        }
        VirtualProtect(&aVtable[aSlot], sizeof(void*), old, &old);
    }
    return previous;
}

Wish* Find(uint32_t aProxy, uint32_t aIndex, bool aCreate)
{
    Wish* free = nullptr;
    for (auto& w : g_wishes)
    {
        if (w.proxy == aProxy && w.index == aIndex)
        {
            return &w;
        }
        if (!w.proxy && !free)
        {
            free = &w;
        }
    }
    if (aCreate && free)
    {
        *free = {};
        free->proxy = aProxy;
        free->index = aIndex;
        free->gravity = -1;
        free->collide = -1;
        free->back.gravity = -1;
        return free;
    }
    return nullptr;
}
} // namespace

namespace MNC::PhysXBody
{
void Init(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk)
{
    g_handle = aHandle;
    g_sdk = aSdk;
    auto module = GetModuleHandleW(L"PhysX3_x64.dll");
    if (module)
    {
        g_getPhysics = reinterpret_cast<PxGetPhysics_t>(GetProcAddress(module, "PxGetPhysics"));
    }
}

// from the script side (main thread) until a scene exists; patches the shared NpScene vtable once,
// chaining to whatever was in the slots (another plugin's hook included)
void EnsureHooked()
{
    if (g_hooked.load(std::memory_order_acquire))
    {
        return;
    }
    if (!g_getPhysics)
    {
        auto module = GetModuleHandleW(L"PhysX3_x64.dll");
        if (module)
        {
            g_getPhysics = reinterpret_cast<PxGetPhysics_t>(GetProcAddress(module, "PxGetPhysics"));
        }
        if (!g_getPhysics)
        {
            return;
        }
    }
    PxPhysics& physics = g_getPhysics();
    if (physics.getNbScenes() == 0)
    {
        return;
    }
    PxScene* scene = nullptr;
    physics.getScenes(&scene, 1, 0);
    if (!scene)
    {
        return;
    }
    g_vtable = *reinterpret_cast<void***>(scene);
    // the originals are set before the detours go in (a step may call them at once)
    g_simulate = reinterpret_cast<Simulate_t>(g_vtable[SLOT_SIMULATE]);
    g_collide = reinterpret_cast<Collide_t>(g_vtable[SLOT_COLLIDE]);
    auto prevSim = PatchSlot(g_vtable, SLOT_SIMULATE, reinterpret_cast<void*>(&Simulate_Detour));
    auto prevCol = PatchSlot(g_vtable, SLOT_COLLIDE, reinterpret_cast<void*>(&Collide_Detour));
    if (!prevSim || !prevCol)
    {
        if (g_sdk)
        {
            g_sdk->logger->Warn(g_handle, "v3: could not patch the PhysX step; per-step control is off");
        }
        return;
    }
    g_simulate = reinterpret_cast<Simulate_t>(prevSim);
    g_collide = reinterpret_cast<Collide_t>(prevCol);
    g_hooked.store(true, std::memory_order_release);
    if (g_sdk)
    {
        g_sdk->logger->InfoF(g_handle, "v3: PhysX step hook on (%u scene(s))", physics.getNbScenes());
    }
}

bool IsHooked()
{
    return g_hooked.load(std::memory_order_acquire);
}

bool SetGravity(uint32_t aProxy, uint32_t aIndex, bool aOn)
{
    EnsureHooked();
    AcquireSRWLockExclusive(&g_lock);
    auto w = Find(aProxy, aIndex, true);
    if (w)
    {
        w->gravity = aOn ? 1 : 0;
        w->restore = w->restore || !aOn;
        w->until = GetTickCount64() + HOLD_MS;
    }
    ReleaseSRWLockExclusive(&g_lock);
    return w != nullptr && IsHooked();
}

bool SetForce(uint32_t aProxy, uint32_t aIndex, const float aForce[3], const float aTorque[3])
{
    g_lastScript.store(GetTickCount64(), std::memory_order_relaxed);
    EnsureHooked();
    AcquireSRWLockExclusive(&g_lock);
    auto w = Find(aProxy, aIndex, true);
    if (w)
    {
        std::memcpy(w->force, aForce, sizeof(w->force));
        std::memcpy(w->torque, aTorque, sizeof(w->torque));
        w->until = GetTickCount64() + HOLD_MS;
    }
    ReleaseSRWLockExclusive(&g_lock);
    return w != nullptr && IsHooked();
}

bool SetCollision(uint32_t aProxy, uint32_t aIndex, bool aOn)
{
    EnsureHooked();
    AcquireSRWLockExclusive(&g_lock);
    auto w = Find(aProxy, aIndex, true);
    if (w)
    {
        w->collide = aOn ? 1 : 0;
        w->until = GetTickCount64() + HOLD_MS;
    }
    ReleaseSRWLockExclusive(&g_lock);
    return w != nullptr && IsHooked();
}

void Release(uint32_t aProxy, uint32_t aIndex)
{
    AcquireSRWLockExclusive(&g_lock);
    auto w = Find(aProxy, aIndex, false);
    if (w)
    {
        w->until = 0; // the next step restores its gravity and drops it
        std::memset(w->force, 0, sizeof(w->force));
        std::memset(w->torque, 0, sizeof(w->torque));
    }
    ReleaseSRWLockExclusive(&g_lock);
}

bool GetReadback(uint32_t aProxy, uint32_t aIndex, Readback& aOut)
{
    AcquireSRWLockShared(&g_lock);
    bool found = false;
    for (const auto& w : g_wishes)
    {
        if (w.proxy == aProxy && w.index == aIndex)
        {
            aOut = w.back;
            found = true;
            break;
        }
    }
    ReleaseSRWLockShared(&g_lock);
    return found;
}

uint32_t Steps()
{
    return g_steps.load(std::memory_order_relaxed);
}

uint32_t Faults()
{
    return g_faults.load(std::memory_order_relaxed);
}

void Mark(const char* aText)
{
    g_lastScript.store(GetTickCount64(), std::memory_order_relaxed);
    AcquireSRWLockExclusive(&g_markLock);
    strncpy_s(g_mark, sizeof(g_mark), aText ? aText : "", _TRUNCATE);
    ReleaseSRWLockExclusive(&g_markLock);
}

void StartWatchdog()
{
    static std::atomic<bool> started{false};
    bool expected = false;
    if (started.compare_exchange_strong(expected, true))
    {
        HANDLE th = CreateThread(nullptr, 0, &WatchThread, nullptr, 0, nullptr);
        if (th)
        {
            CloseHandle(th);
        }
    }
}
} // namespace MNC::PhysXBody
