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

#include <Windows.h>

#include <cstdio>
#include <string>

namespace
{
RED4ext::v1::PluginHandle g_handle = nullptr;
const RED4ext::v1::Sdk* g_sdk = nullptr;

constexpr int32_t VERSION = 1;

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
    Log("MNC Physics v" + std::to_string(VERSION) + " registered (inspect only)");
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
