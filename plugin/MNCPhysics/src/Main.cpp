// =============================================================================
// MNC Physics - Mechs of Night City's RED4ext plugin (optional)
//
// Why it exists (docs: Research: Drones as Real Rigid Bodies, spikes R1-R4):
// the engine's physics body (entPhysicalBodyInterface) has GetLinearVelocity,
// SetLinearVelocity, SetAngularVelocity, GetMass, SetIsSleeping and more, but they are
// registered with no parameters and no return type, so scripts can't call them (the
// compiler doesn't know them; called through Reflection they return nothing). This
// plugin gives MNC what scripts can't reach. Stability rules: the fewest calls possible,
// every call checks its inputs, nothing runs unless MNC asks, and MNC works without it.
//
// v0 (this build) only looks: it never calls an engine function it doesn't know.
//   MNCPhysics_Version()          1 while the plugin is loaded
//   MNCPhysics_Inspect()          logs every function of the physics body and collider
//                                 classes (parameters, return type, flags, and where its
//                                 native code is in the game's executable), so the
//                                 missing calls can be read before anything uses them
//   MNCPhysics_BodyBits(body)     the body handle's own 8 bytes (what it points at)
// The log is red4ext/logs/mncphysics-*.log (under MO2: the overwrite folder).
// =============================================================================
#include <RED4ext/RED4ext.hpp>
#include <RED4ext/RTTITypes.hpp>
#include <RED4ext/Scripting/Functions.hpp>
#include <RED4ext/Scripting/IScriptable.hpp>
#include <RED4ext/Relocation.hpp>
#include <RED4ext/Detail/AddressHashes.hpp>

#include "PhysXBody.hpp"

#include <Windows.h>

#include <cstdio>
#include <string>

namespace
{
RED4ext::v1::PluginHandle g_handle = nullptr;
const RED4ext::v1::Sdk* g_sdk = nullptr;

constexpr int32_t VERSION = 5; // v3.2: a component's body (physical skinned meshes)

void Log(const std::string& aText)
{
    if (g_sdk && g_sdk->logger)
    {
        g_sdk->logger->Info(g_handle, aText.c_str());
    }
}

std::string Hex(uint64_t aValue)
{
    char buf[32];
    std::snprintf(buf, sizeof(buf), "0x%llX", static_cast<unsigned long long>(aValue));
    return buf;
}

// an address as "rva 0x..." when it points into the game's executable, else as is
std::string Rva(uintptr_t aAddr, uintptr_t aBase)
{
    static uintptr_t s_end = 0;
    if (!s_end)
    {
        const auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(aBase);
        const auto nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(aBase + dos->e_lfanew);
        s_end = aBase + nt->OptionalHeader.SizeOfImage;
    }
    if (aAddr >= aBase && aAddr < s_end)
    {
        return "rva:" + Hex(aAddr - aBase);
    }
    return Hex(aAddr);
}

std::string TypeName(RED4ext::CProperty* aProp)
{
    if (!aProp || !aProp->type)
    {
        return "?";
    }
    return aProp->type->GetName().ToString();
}

// the native code behind a registered function (the engine's handler table, by index)
uintptr_t HandlerOf(RED4ext::CClassFunction* aFunc)
{
    using Handler_t = void (*)(void*, RED4ext::CStackFrame&, void*, RED4ext::rtti::IType*);
    static RED4ext::UniversalRelocPtr<Handler_t*> handlers(RED4ext::Detail::AddressHashes::CBaseFunction_Handlers);
    Handler_t* table = handlers;
    if (!table || !aFunc)
    {
        return 0;
    }
    // the index the engine itself uses (the virtual, as the SDK's ExecuteNative does; v0.2
    // read the regIndex field and found nothing)
    return reinterpret_cast<uintptr_t>(table[aFunc->GetRegIndex()]);
}

int32_t DescribeClass(const char* aName)
{
    auto rtti = RED4ext::CRTTISystem::Get();
    auto cls = rtti ? rtti->GetClass(aName) : nullptr;
    if (!cls)
    {
        Log(std::string("inspect: ") + aName + " not found");
        return 0;
    }
    const auto base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    Log(std::string("inspect: ") + aName + ", " + std::to_string(cls->funcs.size()) + " functions, exe base " +
        Hex(base));
    int32_t n = 0;
    for (auto func : cls->funcs)
    {
        if (!func)
        {
            continue;
        }
        std::string params;
        for (auto p : func->params)
        {
            if (!params.empty())
            {
                params += ", ";
            }
            params += std::string(p && p->name.ToString() ? p->name.ToString() : "?") + ": " + TypeName(p);
        }
        const auto handler = HandlerOf(func);
        uint32_t flagBits = 0;
        std::memcpy(&flagBits, &func->flags, sizeof(flagBits));
        // v0 found the handler table empty for these: class natives run through their
        // invokable (IFunction::GetInvokable, whose vtable slot 2 is Execute). Its vtable,
        // its Execute and its first fields (where a wrapped native pointer would sit), as
        // offsets into the game's executable where they point into it.
        std::string inv = "none";
        auto invokable = func->GetInvokable();
        if (invokable)
        {
            const auto obj = reinterpret_cast<const uintptr_t*>(invokable);
            const auto vtbl = reinterpret_cast<const uintptr_t*>(obj[0]);
            inv = "vtbl " + Rva(obj[0], base) + " slots";
            for (int i = 0; i < 6; ++i)
            {
                inv += " " + Rva(vtbl[i], base);
            }
            inv += " fields " + Rva(obj[1], base) + " " + Rva(obj[2], base) + " " + Rva(obj[3], base);
        }
        Log("inspect:   " + std::string(func->shortName.ToString()) + "(" + params + ")" +
            (func->returnType ? " -> " + TypeName(func->returnType) : "") + "  flags " + Hex(flagBits) +
            "  regIndex " + std::to_string(func->regIndex) + " / " + std::to_string(func->GetRegIndex()) +
            "  table " + Rva(handler, base) + "  invokable " + inv);
        ++n;
    }
    return n;
}

// ---- natives ------------------------------------------------------------------------
void Version(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    aFrame->code++; // ParamEnd
    if (aOut)
    {
        *aOut = VERSION;
    }
}

void Inspect(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    aFrame->code++; // ParamEnd
    int32_t n = 0;
    for (auto name : {"entPhysicalBodyInterface", "entColliderComponent", "entPhysicalMeshComponent",
                      "entIPlacedComponent"})
    {
        n += DescribeClass(name);
    }
    if (aOut)
    {
        *aOut = RED4ext::CString(("inspected " + std::to_string(n) + " functions").c_str());
    }
}

void BodyBits(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    RED4ext::Handle<RED4ext::IScriptable> body;
    RED4ext::GetParameter(aFrame, &body);
    aFrame->code++; // ParamEnd
    std::string text = "none";
    if (body)
    {
        const auto raw = reinterpret_cast<const uint8_t*>(body.instance);
        uint64_t bits = 0;
        std::memcpy(&bits, raw + 0x40, sizeof(bits));
        text = "class " + std::string(body->GetType()->GetName().ToString()) + ", bytes 40-47 " + Hex(bits);
    }
    Log("body bits: " + text);
    if (aOut)
    {
        *aOut = RED4ext::CString(text.c_str());
    }
}

// ---- v1: the body's buffered physics state (from the Wind Framework session's map of
// the 2.31 executable, docs PHYSICS_RE_FINDINGS.md; checked here against the disassembly
// of the engine's own SetLinearVelocity thunk). A body handle holds the physics proxy id
// at +0x40 and the body index at +0x44; the engine's setters lock the proxy, write one
// state field and unlock; its getters read through the proxy manager.
struct ProxyAccess
{
    void* buf;
    void* aux;
    uint32_t proxyId;
};

using Lock_t = ProxyAccess* (*)(void* aOut, uint32_t aProxyId);
using Write_t = void (*)(uint32_t aProxyId, void* aBuf, void* aAux, uint32_t aBodyIndex, uint32_t aShapeIndex,
                         uint32_t aStateId, const void* aData, uint32_t aSize, bool aFlag);
using Unlock_t = void (*)(ProxyAccess* aAccess);
using Readable_t = bool (*)(void* aManager, uint32_t aProxyId);
using GetVec_t = RED4ext::Vector3* (*)(RED4ext::Vector3* aOut, uint32_t aProxyId, uint32_t aBodyIndex);

constexpr uint32_t STATE_LINEAR_VELOCITY = 4;
constexpr uint32_t STATE_ANGULAR_VELOCITY = 5;
constexpr uint32_t STATE_IS_SLEEPING = 0x0D;

// the proxy id and body index of a script body handle, if it is one and is live
bool BodyIds(const RED4ext::Handle<RED4ext::IScriptable>& aBody, uint32_t& aProxy, uint32_t& aIndex)
{
    if (!aBody || !aBody.instance)
    {
        return false;
    }
    static auto bodyClass = RED4ext::CRTTISystem::Get()->GetClass("entPhysicalBodyInterface");
    if (!bodyClass || aBody->GetType() != bodyClass)
    {
        return false;
    }
    const auto raw = reinterpret_cast<const uint8_t*>(aBody.instance);
    std::memcpy(&aProxy, raw + 0x40, sizeof(aProxy));
    std::memcpy(&aIndex, raw + 0x44, sizeof(aIndex));
    if (aProxy == 0)
    {
        return false;
    }
    static RED4ext::UniversalRelocPtr<void*> manager(37956006);
    static RED4ext::UniversalRelocFunc<Readable_t> readable(3901166127);
    void* m = manager;
    return m && readable(m, aProxy);
}

bool WriteState(uint32_t aProxy, uint32_t aIndex, uint32_t aState, const void* aData, uint32_t aSize)
{
    static RED4ext::UniversalRelocFunc<Lock_t> lock(1210388152);
    static RED4ext::UniversalRelocFunc<Write_t> write(1403400784);
    static RED4ext::UniversalRelocFunc<Unlock_t> unlock(200045);
    alignas(16) uint8_t scratch[0x40] = {};
    auto access = lock(scratch, aProxy);
    if (!access)
    {
        return false;
    }
    const bool ok = access->buf != nullptr;
    if (ok)
    {
        write(access->proxyId, access->buf, access->aux, aIndex, 0, aState, aData, aSize, false);
    }
    unlock(access);
    return ok;
}

void SetVec(RED4ext::CStackFrame* aFrame, bool* aOut, uint32_t aState)
{
    RED4ext::Handle<RED4ext::IScriptable> body;
    RED4ext::Vector4 v{};
    RED4ext::GetParameter(aFrame, &body);
    RED4ext::GetParameter(aFrame, &v);
    aFrame->code++; // ParamEnd
    uint32_t proxy = 0, index = 0;
    bool ok = false;
    if (BodyIds(body, proxy, index))
    {
        const RED4ext::Vector3 v3{v.X, v.Y, v.Z};
        ok = WriteState(proxy, index, aState, &v3, sizeof(v3));
    }
    if (aOut)
    {
        *aOut = ok;
    }
}

void GetVec(RED4ext::CStackFrame* aFrame, RED4ext::Vector4* aOut, uint32_t aHash)
{
    RED4ext::Handle<RED4ext::IScriptable> body;
    RED4ext::GetParameter(aFrame, &body);
    aFrame->code++; // ParamEnd
    RED4ext::Vector4 result{0.f, 0.f, 0.f, 0.f};
    uint32_t proxy = 0, index = 0;
    if (BodyIds(body, proxy, index))
    {
        RED4ext::UniversalRelocFunc<GetVec_t> get(aHash);
        RED4ext::Vector3 v3{};
        get(&v3, proxy, index);
        result = {v3.X, v3.Y, v3.Z, 0.f};
    }
    if (aOut)
    {
        *aOut = result;
    }
}

void SetLinearVelocity(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    SetVec(aFrame, aOut, STATE_LINEAR_VELOCITY);
}

void SetAngularVelocity(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    SetVec(aFrame, aOut, STATE_ANGULAR_VELOCITY);
}

void GetLinearVelocity(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::Vector4* aOut, int64_t)
{
    GetVec(aFrame, aOut, 1360335866);
}

void GetAngularVelocity(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::Vector4* aOut, int64_t)
{
    GetVec(aFrame, aOut, 1763775593);
}

void SetSleeping(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    RED4ext::Handle<RED4ext::IScriptable> body;
    bool sleeping = false;
    RED4ext::GetParameter(aFrame, &body);
    RED4ext::GetParameter(aFrame, &sleeping);
    aFrame->code++; // ParamEnd
    uint32_t proxy = 0, index = 0;
    bool ok = false;
    if (BodyIds(body, proxy, index))
    {
        const uint8_t value = sleeping ? 1 : 0;
        ok = WriteState(proxy, index, STATE_IS_SLEEPING, &value, sizeof(value));
    }
    if (aOut)
    {
        *aOut = ok;
    }
}

// ---- v3: per-physics-step wishes (PhysXBody.cpp) ---------------------------------
bool ReadBody(RED4ext::CStackFrame* aFrame, uint32_t& aProxy, uint32_t& aIndex)
{
    RED4ext::Handle<RED4ext::IScriptable> body;
    RED4ext::GetParameter(aFrame, &body);
    return BodyIds(body, aProxy, aIndex);
}

void SetGravity(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    uint32_t proxy = 0, index = 0;
    const bool ok = ReadBody(aFrame, proxy, index);
    bool on = true;
    RED4ext::GetParameter(aFrame, &on);
    aFrame->code++; // ParamEnd
    const bool done = ok && MNC::PhysXBody::SetGravity(proxy, index, on);
    if (aOut)
    {
        *aOut = done;
    }
}

void SetForce(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    uint32_t proxy = 0, index = 0;
    const bool ok = ReadBody(aFrame, proxy, index);
    RED4ext::Vector4 f{}, t{};
    RED4ext::GetParameter(aFrame, &f);
    RED4ext::GetParameter(aFrame, &t);
    aFrame->code++; // ParamEnd
    const float force[3] = {f.X, f.Y, f.Z};
    const float torque[3] = {t.X, t.Y, t.Z};
    const bool done = ok && MNC::PhysXBody::SetForce(proxy, index, force, torque);
    if (aOut)
    {
        *aOut = done;
    }
}

void SetCollision(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    uint32_t proxy = 0, index = 0;
    const bool ok = ReadBody(aFrame, proxy, index);
    bool on = true;
    RED4ext::GetParameter(aFrame, &on);
    aFrame->code++; // ParamEnd
    const bool done = ok && MNC::PhysXBody::SetCollision(proxy, index, on);
    if (aOut)
    {
        *aOut = done;
    }
}

void ReleaseBody(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    uint32_t proxy = 0, index = 0;
    const bool ok = ReadBody(aFrame, proxy, index);
    aFrame->code++; // ParamEnd
    if (ok)
    {
        MNC::PhysXBody::Release(proxy, index);
    }
    if (aOut)
    {
        *aOut = ok;
    }
}

void StepVelocity(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::Vector4* aOut, int64_t)
{
    uint32_t proxy = 0, index = 0;
    const bool ok = ReadBody(aFrame, proxy, index);
    aFrame->code++; // ParamEnd
    MNC::PhysXBody::Readback back{};
    if (aOut)
    {
        *aOut = ok && MNC::PhysXBody::GetReadback(proxy, index, back)
                    ? RED4ext::Vector4{back.vel[0], back.vel[1], back.vel[2], 0.f}
                    : RED4ext::Vector4{0.f, 0.f, 0.f, 0.f};
    }
}

void StepSpin(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::Vector4* aOut, int64_t)
{
    uint32_t proxy = 0, index = 0;
    const bool ok = ReadBody(aFrame, proxy, index);
    aFrame->code++; // ParamEnd
    MNC::PhysXBody::Readback back{};
    if (aOut)
    {
        *aOut = ok && MNC::PhysXBody::GetReadback(proxy, index, back)
                    ? RED4ext::Vector4{back.spin[0], back.spin[1], back.spin[2], 0.f}
                    : RED4ext::Vector4{0.f, 0.f, 0.f, 0.f};
    }
}

void StepInfo(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    uint32_t proxy = 0, index = 0;
    const bool ok = ReadBody(aFrame, proxy, index);
    aFrame->code++; // ParamEnd
    std::string text = std::string("hook ") + (MNC::PhysXBody::IsHooked() ? "on" : "OFF") + ", " +
                       std::to_string(MNC::PhysXBody::Steps()) + " physics steps, " +
                       std::to_string(MNC::PhysXBody::Faults()) + " faults caught";
    MNC::PhysXBody::Readback back{};
    if (!ok)
    {
        text += ", body not live";
    }
    else if (MNC::PhysXBody::GetReadback(proxy, index, back))
    {
        text += ", body driven " + std::to_string(back.steps) + " steps, gravity " +
                (back.gravity < 0 ? "?" : (back.gravity ? "on" : "off")) + ", put back by others " +
                std::to_string(back.reset) + " times";
    }
    else
    {
        text += ", body not driven";
    }
    if (aOut)
    {
        *aOut = RED4ext::CString(text.c_str());
    }
}

// ---- v3.2: a component's physics body, for components scripts can't ask -------------
// entPhysicalSkinnedMeshComponent.CreatePhysicalBodyInterface is registered with no return
// type, so scripts (and Codeware's Reflection) get nothing back. Its native still makes the
// body handle; called here with a result slot of the handle type, it is read back. The
// Griffin's body and wings are such meshes (kinematic, inside its physics body: a12 threw it
// into the ground at 23 m/s the moment the body went live, like the Octant's pods in a10).
bool ExecuteGuarded(RED4ext::CBaseFunction* aFunc, RED4ext::CStack* aStack)
{
    __try
    {
        return aFunc->Execute(aStack);
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

void ComponentBody(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame,
                   RED4ext::Handle<RED4ext::IScriptable>* aOut, int64_t)
{
    RED4ext::Handle<RED4ext::IScriptable> comp;
    int32_t index = 0;
    RED4ext::GetParameter(aFrame, &comp);
    RED4ext::GetParameter(aFrame, &index);
    aFrame->code++; // ParamEnd
    RED4ext::Handle<RED4ext::IScriptable> body;
    std::string why = "no component";
    if (comp && comp.instance)
    {
        auto rtti = RED4ext::CRTTISystem::Get();
        auto cls = comp->GetType();
        auto func = cls ? cls->GetFunction("CreatePhysicalBodyInterface") : nullptr;
        auto handleType = rtti->GetType("handle:entPhysicalBodyInterface");
        if (!func)
        {
            why = std::string(cls ? cls->GetName().ToString() : "?") + " has no CreatePhysicalBodyInterface";
        }
        else if (!handleType)
        {
            why = "no handle type";
        }
        else
        {
            uint32_t idx = static_cast<uint32_t>(index < 0 ? 0 : index);
            RED4ext::CStackType arg;
            const bool takesIndex = func->params.Size() > 0;
            if (takesIndex)
            {
                arg.type = func->params[0]->type;
                arg.value = &idx;
            }
            RED4ext::CStackType result;
            result.type = handleType;
            result.value = &body;
            RED4ext::CStack stack(comp.instance, takesIndex ? &arg : nullptr, takesIndex ? 1u : 0u, &result);
            const bool ran = ExecuteGuarded(func, &stack);
            uint32_t proxy = 0, bodyIndex = 0;
            const bool live = body && BodyIds(body, proxy, bodyIndex);
            why = std::string(cls->GetName().ToString()) + (ran ? " ran" : " FAILED") + ", " +
                  (body ? (live ? "body proxy " + std::to_string(proxy) + " index " + std::to_string(bodyIndex)
                                : "a handle that is not a live body")
                        : "no handle back");
            if (body && !live)
            {
                body.Reset();
            }
        }
    }
    Log("component body: " + why);
    if (aOut)
    {
        *aOut = body;
    }
}

template<typename T>
void Global(const char* aName, RED4ext::ScriptingFunction_t<T> aFunc, const char* aReturn,
            std::initializer_list<std::pair<const char*, const char*>> aParams)
{
    auto f = RED4ext::CGlobalFunction::Create(aName, aName, aFunc);
    for (auto& p : aParams)
    {
        f->AddParam(p.first, p.second);
    }
    if (aReturn)
    {
        f->SetReturnType(aReturn);
    }
    RED4ext::CRTTISystem::Get()->RegisterFunction(f);
}

void RegisterTypes()
{
}

void PostRegisterTypes()
{
    auto rtti = RED4ext::CRTTISystem::Get();
    {
        auto f = RED4ext::CGlobalFunction::Create("MNCPhysics_Version", "MNCPhysics_Version", &Version);
        f->SetReturnType("Int32");
        rtti->RegisterFunction(f);
    }
    {
        auto f = RED4ext::CGlobalFunction::Create("MNCPhysics_Inspect", "MNCPhysics_Inspect", &Inspect);
        f->SetReturnType("String");
        rtti->RegisterFunction(f);
    }
    {
        auto f = RED4ext::CGlobalFunction::Create("MNCPhysics_BodyBits", "MNCPhysics_BodyBits", &BodyBits);
        f->AddParam("handle:entPhysicalBodyInterface", "body");
        f->SetReturnType("String");
        rtti->RegisterFunction(f);
    }
    Global("MNCPhysics_SetLinearVelocity", &SetLinearVelocity, "Bool",
           {{"handle:entPhysicalBodyInterface", "body"}, {"Vector4", "velocity"}});
    Global("MNCPhysics_SetAngularVelocity", &SetAngularVelocity, "Bool",
           {{"handle:entPhysicalBodyInterface", "body"}, {"Vector4", "spin"}});
    Global("MNCPhysics_GetLinearVelocity", &GetLinearVelocity, "Vector4", {{"handle:entPhysicalBodyInterface", "body"}});
    Global("MNCPhysics_GetAngularVelocity", &GetAngularVelocity, "Vector4",
           {{"handle:entPhysicalBodyInterface", "body"}});
    Global("MNCPhysics_SetSleeping", &SetSleeping, "Bool",
           {{"handle:entPhysicalBodyInterface", "body"}, {"Bool", "sleeping"}});
    Global("MNCPhysics_SetGravity", &SetGravity, "Bool", {{"handle:entPhysicalBodyInterface", "body"}, {"Bool", "on"}});
    Global("MNCPhysics_SetForce", &SetForce, "Bool",
           {{"handle:entPhysicalBodyInterface", "body"}, {"Vector4", "force"}, {"Vector4", "torque"}});
    Global("MNCPhysics_Release", &ReleaseBody, "Bool", {{"handle:entPhysicalBodyInterface", "body"}});
    Global("MNCPhysics_SetCollision", &SetCollision, "Bool",
           {{"handle:entPhysicalBodyInterface", "body"}, {"Bool", "on"}});
    Global("MNCPhysics_ComponentBody", &ComponentBody, "handle:entPhysicalBodyInterface",
           {{"handle:entIComponent", "component"}, {"Int32", "index"}});
    Global("MNCPhysics_StepVelocity", &StepVelocity, "Vector4", {{"handle:entPhysicalBodyInterface", "body"}});
    Global("MNCPhysics_StepSpin", &StepSpin, "Vector4", {{"handle:entPhysicalBodyInterface", "body"}});
    Global("MNCPhysics_StepInfo", &StepInfo, "String", {{"handle:entPhysicalBodyInterface", "body"}});
    Log("MNC Physics v" + std::to_string(VERSION) +
        " registered: velocity and spin, per-step gravity / force / torque");
}

// the plugin's own scripts, next to the DLL: compiled only while the plugin is loaded
void AddScripts()
{
    wchar_t path[MAX_PATH] = {};
    HMODULE self = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&AddScripts), &self) ||
        !GetModuleFileNameW(self, path, MAX_PATH))
    {
        return;
    }
    std::wstring dir(path);
    dir = dir.substr(0, dir.find_last_of(L"\\/")) + L"\\scripts";
    if (g_sdk && g_sdk->scripts)
    {
        g_sdk->scripts->Add(g_handle, dir.c_str());
    }
}
} // namespace

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle, RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    switch (aReason)
    {
    case RED4ext::v1::EMainReason::Load:
    {
        g_handle = aHandle;
        g_sdk = aSdk;
        auto rtti = RED4ext::CRTTISystem::Get();
        rtti->AddRegisterCallback(RegisterTypes);
        rtti->AddPostRegisterCallback(PostRegisterTypes);
        AddScripts();
        MNC::PhysXBody::Init(aHandle, aSdk);
        break;
    }
    case RED4ext::v1::EMainReason::Unload:
    {
        break;
    }
    }
    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"MNC Physics";
    aInfo->author = L"Mechs of Night City";
    aInfo->version = RED4EXT_V1_SEMVER(0, 1, 0);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_LATEST;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}
