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

#include <PxPhysics.h>
#include <PxRigidDynamic.h>
#include <PxScene.h>
#include <PxSceneLock.h>

using namespace physx;

namespace
{
constexpr std::size_t SLOT_SIMULATE = 56; // PxScene vtable (3.4 order, checked in PhysX3_x64.dll)
constexpr std::size_t SLOT_COLLIDE = 58;
constexpr std::size_t MAX_BODIES = 16;
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

void Drive(PxScene* aScene)
{
    g_steps.fetch_add(1, std::memory_order_relaxed);
    const auto now = GetTickCount64();
    AcquireSRWLockExclusive(&g_lock);
    for (auto& w : g_wishes)
    {
        if (!w.proxy)
        {
            continue;
        }
        auto actor = ActorOf(w.proxy, w.index, aScene);
        const bool expired = w.until <= now;
        if (!actor)
        {
            if (expired)
            {
                w = {};
            }
            continue;
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
            w = {};
            continue;
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
    ReleaseSRWLockExclusive(&g_lock);
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

void PatchSlot(void** aVtable, std::size_t aSlot, void* aValue)
{
    DWORD old = 0;
    if (VirtualProtect(&aVtable[aSlot], sizeof(void*), PAGE_READWRITE, &old))
    {
        InterlockedExchangePointer(&aVtable[aSlot], aValue);
        VirtualProtect(&aVtable[aSlot], sizeof(void*), old, &old);
    }
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
    g_simulate = reinterpret_cast<Simulate_t>(g_vtable[SLOT_SIMULATE]);
    g_collide = reinterpret_cast<Collide_t>(g_vtable[SLOT_COLLIDE]);
    PatchSlot(g_vtable, SLOT_SIMULATE, reinterpret_cast<void*>(&Simulate_Detour));
    PatchSlot(g_vtable, SLOT_COLLIDE, reinterpret_cast<void*>(&Collide_Detour));
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
} // namespace MNC::PhysXBody
