// OverlayMapNative: optional engine calls for OverlayMap (waypoints). See
// docs/superpowers/specs/2026-11-02-overlaymap-waypoints-design.md.
//
// Built with mingw-w64 (GCC, Itanium C++ ABI) against an MSVC-built game: never make a C++ virtual call on an engine
// object whose class declares its virtual destructor before the slot used (GCC reserves two destructor slots, MSVC
// one). IRTTISystem declares it last, so its calls are safe; IFunction declares it second, so its later slots are read
// from the vtable by MSVC index (VSlot).
#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Functions.hpp>
#include <RED4ext/Scripting/Stack.hpp>
#include <RED4ext/CString.hpp>

#include "Resolve.hpp"

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <windows.h>

namespace
{
const RED4ext::v1::Sdk* gSdk = nullptr;
RED4ext::v1::PluginHandle gPlugin = nullptr;

void Log(const char* aText)
{
    if (gSdk)
        gSdk->logger->Info(gPlugin, aText);
}

template<typename R, typename... A>
R VSlot(void* aObject, int aIndex, A... aArgs)
{
    auto vtable = *reinterpret_cast<void***>(aObject);
    return reinterpret_cast<R (*)(void*, A...)>(vtable[aIndex])(aObject, aArgs...);
}

uintptr_t ImageBase()
{
    return reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
}

// Reads 8 bytes only if the page is committed and readable (probing engine memory the plugin didn't allocate).
bool SafeRead(uintptr_t aAddress, uint64_t& aOut)
{
    MEMORY_BASIC_INFORMATION mbi{};
    if (!VirtualQuery(reinterpret_cast<void*>(aAddress), &mbi, sizeof(mbi)) || mbi.State != MEM_COMMIT)
        return false;
    constexpr DWORD readable = PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READ |
                               PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
    if (!(mbi.Protect & readable) || (mbi.Protect & PAGE_GUARD))
        return false;
    auto end = reinterpret_cast<uintptr_t>(mbi.BaseAddress) + mbi.RegionSize;
    if (aAddress + 8 > end)
        return false;
    aOut = *reinterpret_cast<uint64_t*>(aAddress);
    return true;
}

// RED4ext's address for a hash, or 0. The SDK's UniversalReloc* show an error and terminate the game on an unknown hash;
// a future RED4ext may drop one of these, and that must turn the feature off, not close the game.
uintptr_t ResolveHash(uint32_t aHash)
{
    using ResolveFunc = uintptr_t (*)(uint32_t);
    static ResolveFunc resolve = []() -> ResolveFunc {
        auto module = GetModuleHandleW(L"RED4ext.dll");
        return module ? reinterpret_cast<ResolveFunc>(GetProcAddress(module, "RED4ext_ResolveAddress")) : nullptr;
    }();
    return resolve ? resolve(aHash) : 0;
}

void Version(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t);

// The engine's native handler tables (game 2.5, inline arrays in .data, entry = body, index = regIndex from one shared
// counter): static and global natives go into table A, member natives into table B. Table A is read from the
// NativeGlobalFunction ctor (symbol-named hash RED4ext keeps current), pattern-checked, then calibrated on our own
// registered native. Table B is where the SDK's CBaseFunction_Handlers hash points (the SDK wrongly dereferences it).
// Any mismatch → 0 and every caller treats the engine as unknown.
uintptr_t StaticTable()
{
    static uintptr_t cached = 1; // 1 = not resolved yet
    if (cached != 1)
        return cached;
    cached = 0;
    auto ctorAddr = ResolveHash(RED4ext::Detail::AddressHashes::CGlobalFunction_ctor);
    if (!ctorAddr)
        return 0;
    uint8_t code[0x80];
    for (std::size_t i = 0; i < sizeof(code); i += 8)
    {
        uint64_t v = 0;
        if (!SafeRead(ctorAddr + i, v))
            return 0;
        std::memcpy(code + i, &v, 8);
    }
    auto table = nmn::HandlerTableFromCtor(code, sizeof(code), ctorAddr);
    auto self = RED4ext::CRTTISystem::Get()->GetFunction("OverlayMapNative_Version");
    uint64_t entry = 0;
    if (!table || !self || !SafeRead(table + 8ull * self->regIndex, entry) ||
        entry != reinterpret_cast<uint64_t>(&Version))
        return 0;
    cached = table;
    return cached;
}

uintptr_t MemberTable()
{
    if (!StaticTable())
        return 0; // the engine layout isn't the one we know
    static const uintptr_t table = ResolveHash(RED4ext::Detail::AddressHashes::CBaseFunction_Handlers);
    return table;
}

// [start, end) of the game exe's code section.
bool InGameCode(uintptr_t aAddress)
{
    auto image = ImageBase();
    auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
    auto nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(image + dos->e_lfanew);
    auto section = IMAGE_FIRST_SECTION(nt);
    for (unsigned i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++section)
        if (std::memcmp(section->Name, ".text", 6) == 0)
            return aAddress >= image + section->VirtualAddress &&
                   aAddress < image + section->VirtualAddress + section->Misc.VirtualSize;
    return false;
}

// The native body of a function registered by the game, or 0 (unknown layout, not native, or not in game code).
uintptr_t NativeBody(RED4ext::CBaseFunction* aFunc)
{
    if (!aFunc || !aFunc->flags.isNative)
        return 0;
    auto table = aFunc->flags.isStatic ? StaticTable() : MemberTable();
    if (!table)
        return 0;
    auto index = VSlot<uint32_t>(aFunc, 3); // IFunction::GetRegIndex, MSVC slot 3 (0x18)
    uint64_t body = 0;
    if (!SafeRead(table + 8ull * index, body) || !InGameCode(static_cast<uintptr_t>(body)))
        return 0;
    return static_cast<uintptr_t>(body);
}

RED4ext::CClass* WorldMapController()
{
    auto rtti = RED4ext::CRTTISystem::Get();
    auto cls = rtti->GetClassByScriptName("WorldMapMenuGameController");
    if (!cls)
        cls = rtti->GetClass("gameuiWorldMapMenuGameController");
    return cls;
}

std::string RvaLine()
{
    auto cls = WorldMapController();
    if (!cls)
        return "no class";
    if (!StaticTable())
        return "no handler table";
    std::string out;
    const char* names[] = {"TrackMappin", "UntrackMappin", "TrackCustomPositionMappin", "UntrackCustomPositionMappin"};
    for (auto name : names)
    {
        auto func = cls->GetFunction(name);
        auto body = NativeBody(func);
        char buf[96];

        std::snprintf(buf, sizeof(buf), "%s%s=0x%llx", out.empty() ? "" : "|", name,
                      body ? static_cast<unsigned long long>(body - ImageBase()) : 0ULL);
        out += buf;
    }
    return out;
}


// Copies `aSize` (multiple of 8) bytes of engine code, or false if any page isn't readable.
bool SafeCopy(uintptr_t aAddress, uint8_t* aOut, std::size_t aSize)
{
    for (std::size_t i = 0; i < aSize; i += 8)
    {
        uint64_t v = 0;
        if (!SafeRead(aAddress + i, v))
            return false;
        std::memcpy(aOut + i, &v, 8);
    }
    return true;
}

// The mappin system's track/untrack virtuals, found by following the world map's own natives (game 2.5):
//   WorldMapMenuGameController.TrackMappin body → its internal → `call [rax+track]` / `call [rax+untrack]`,
//   MappinSystem.UntrackMappin body (a thunk) → the untrack implementation, which must sit in the untrack slot of the
//   instance we are handed before we call anything on it.
struct Engine
{
    bool ok = false;
    nmn::TrackSlots slots;
    uintptr_t untrackImpl = 0;
    const char* why = "not resolved";
};

const Engine& ResolveEngineOnce();

// Resolves once and logs the outcome once (a game update shows up as one line naming the step that failed).
const Engine& ResolveEngine()
{
    static bool logged = false;
    auto& engine = ResolveEngineOnce();
    if (!logged)
    {
        logged = true;
        std::string line = std::string("engine: ") + engine.why;
        Log(line.c_str());
    }
    return engine;
}

const Engine& ResolveEngineOnce()
{
    static Engine engine;
    static bool done = false;
    if (done)
        return engine;
    done = true;
    auto rtti = RED4ext::CRTTISystem::Get();
    auto worldMap = WorldMapController();
    auto mappins = rtti->GetClass("gamemappinsMappinSystem");
    if (!worldMap || !mappins)
        return engine.why = "classes not found", engine;
    if (!StaticTable())
        return engine.why = "handler tables not recognised", engine;

    uint8_t body[0x60];
    auto trackBody = NativeBody(worldMap->GetFunction("TrackMappin"));
    if (!trackBody || !SafeCopy(trackBody, body, sizeof(body)))
        return engine.why = "TrackMappin body unreadable", engine;
    auto internal = nmn::TrackInternalFromBody(body, sizeof(body), trackBody);
    uint8_t code[0x140];
    if (!internal || !InGameCode(internal) || !SafeCopy(internal, code, sizeof(code)))
        return engine.why = "TrackMappin body not recognised", engine;
    engine.slots = nmn::SlotsFromTrackInternal(code, sizeof(code));
    if (!engine.slots.ok)
        return engine.why = "track internal not recognised", engine;

    uint8_t thunk[8];
    auto untrackBody = NativeBody(mappins->GetFunction("UntrackMappin"));
    if (!untrackBody || !SafeCopy(untrackBody, thunk, sizeof(thunk)))
        return engine.why = "MappinSystem.UntrackMappin body unreadable", engine;
    engine.untrackImpl = nmn::JumpTargetOfThunk(thunk, sizeof(thunk), untrackBody);
    if (!engine.untrackImpl || !InGameCode(engine.untrackImpl))
        return engine.why = "MappinSystem.UntrackMappin body not recognised", engine;

    engine.ok = true;
    engine.why = "ok";
    return engine;
}

// Tracks a mappin the way the world map does. Refuses unless the instance's untrack slot holds the untrack
// implementation (proves the object, its vtable and the slot numbering are the ones we resolved).
bool TrackOn(RED4ext::IScriptable* aSystem, uint64_t aId)
{
    auto& engine = ResolveEngine();
    if (!engine.ok || !aSystem || aId == 0)
        return false;
    uint64_t vtable = 0, untrack = 0, track = 0;
    auto object = reinterpret_cast<uintptr_t>(aSystem);
    if (!SafeRead(object, vtable) || !SafeRead(vtable + engine.slots.untrack, untrack) ||
        untrack != engine.untrackImpl || !SafeRead(vtable + engine.slots.track, track) ||
        !InGameCode(static_cast<uintptr_t>(track)))
        return false;
    reinterpret_cast<void (*)(void*, uint64_t)>(track)(aSystem, aId);
    return true;
}

// Reads the next script parameter the way the game's own native bodies do (opcode handlers are table A's first 256
// entries), instead of the SDK's OpcodeHandlers relocation.
template<typename T>
bool ReadParam(RED4ext::CStackFrame* aFrame, T* aOut)
{
    auto table = StaticTable();
    if (!table)
        return false;
    aFrame->data = nullptr;
    aFrame->dataType = nullptr;
    aFrame->currentParam++;
    auto opcode = static_cast<uint8_t>(*aFrame->code++);
    using Op_t = void (*)(RED4ext::IScriptable*, RED4ext::CStackFrame*, void*, void*);
    auto op = reinterpret_cast<Op_t>(reinterpret_cast<uint64_t*>(table)[opcode]);
    op(aFrame->context, aFrame, aOut, nullptr);
    return true;
}

static_assert(offsetof(RED4ext::CStackFrame, data) == 0x30 && offsetof(RED4ext::CStackFrame, dataType) == 0x38 &&
                  offsetof(RED4ext::CStackFrame, context) == 0x40 &&
                  offsetof(RED4ext::CStackFrame, currentParam) == 0x62,
              "CStackFrame layout differs from game 2.5's native bodies");

void Available(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
        *aOut = ResolveEngine().ok;
}

void Why(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
        new (aOut) RED4ext::CString(ResolveEngine().why);
}

void TrackMappin(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    RED4ext::Handle<RED4ext::IScriptable> system;
    uint64_t id = 0;
    bool read = ReadParam(aFrame, &system) && ReadParam(aFrame, &id);
    aFrame->code++; // ParamEnd
    bool ok = read && TrackOn(system.instance, id);
    if (aOut)
        *aOut = ok;
}

void Version(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
        *aOut = 1;
}

void Rvas(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    aFrame->code++;
    auto line = RvaLine();
    if (aOut)
        new (aOut) RED4ext::CString(line.c_str());
}

// Wall clock in ms since the plugin loaded (QueryPerformanceCounter). The engine time scripts can read only ticks every
// 31.25 ms, which makes per-frame motion uneven above 32 FPS.
void NowMs(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float* aOut, int64_t)
{
    aFrame->code++;
    static LARGE_INTEGER freq{}, start{};
    if (!freq.QuadPart)
    {
        QueryPerformanceFrequency(&freq);
        QueryPerformanceCounter(&start);
    }
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    if (aOut)
        *aOut = static_cast<float>(static_cast<double>(now.QuadPart - start.QuadPart) * 1000.0 / static_cast<double>(freq.QuadPart));
}

// Photo pin storage: <game>/r6/storages/OverlayMap/photos.txt, the file RedFileSystem's "OverlayMap" storage used, so
// existing pins carry over. The name is fixed here: scripts can't reach any other file.
std::filesystem::path PhotoFile()
{
    wchar_t exe[MAX_PATH * 4];
    auto n = GetModuleFileNameW(nullptr, exe, static_cast<DWORD>(std::size(exe)));
    if (n == 0 || n >= std::size(exe))
        return {};
    // <game>/bin/x64/Cyberpunk2077.exe
    return std::filesystem::path(exe).parent_path().parent_path().parent_path() / L"r6" / L"storages" / L"OverlayMap" /
           L"photos.txt";
}

void PhotoStoreRead(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    aFrame->code++;
    std::string text;
    auto file = PhotoFile();
    std::ifstream in(file, std::ios::binary);
    if (in)
        text.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    if (aOut)
        new (aOut) RED4ext::CString(text.c_str());
}

// Appends the text as is (the script ends each record with a newline). False when the text can't be read from the
// script call (unknown game build) or the file can't be written.
void PhotoStoreAppend(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    RED4ext::CString text;
    bool read = ReadParam(aFrame, &text);
    aFrame->code++; // ParamEnd
    bool ok = false;
    auto file = PhotoFile();
    if (read && !file.empty())
    {
        std::error_code ec;
        std::filesystem::create_directories(file.parent_path(), ec);
        std::ofstream out(file, std::ios::binary | std::ios::app);
        if (out)
        {
            out.write(text.c_str(), static_cast<std::streamsize>(text.Length()));
            ok = static_cast<bool>(out.flush());
        }
    }
    if (aOut)
        *aOut = ok;
}

RED4ext::CGlobalFunction* Register(const char* aName, void* aFunc, const char* aReturn)
{
    RED4ext::CBaseFunction::Flags flags = {.isNative = true, .isStatic = true};
    auto func = RED4ext::CGlobalFunction::Create(aName, aName, reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(aFunc));
    func->flags = flags;
    func->SetReturnType(aReturn);
    return func;
}

void Commit(RED4ext::CGlobalFunction* aFunc)
{
    RED4ext::CRTTISystem::Get()->RegisterFunction(aFunc);
}

void RegisterTypes()
{
}

void PostRegisterTypes()
{
    Commit(Register("OverlayMapNative_Version", reinterpret_cast<void*>(&Version), "Int32"));
    Commit(Register("OverlayMapNative_Rvas", reinterpret_cast<void*>(&Rvas), "String"));
    Commit(Register("OverlayMapNative_Available", reinterpret_cast<void*>(&Available), "Bool"));
    Commit(Register("OverlayMapNative_Why", reinterpret_cast<void*>(&Why), "String"));
    Commit(Register("OverlayMapNative_NowMs", reinterpret_cast<void*>(&NowMs), "Float"));
    Commit(Register("OverlayMapNative_PhotoStoreRead", reinterpret_cast<void*>(&PhotoStoreRead), "String"));
    auto append = Register("OverlayMapNative_PhotoStoreAppend", reinterpret_cast<void*>(&PhotoStoreAppend), "Bool");
    append->AddParam("String", "text");
    Commit(append);
    auto track = Register("OverlayMapNative_TrackMappin", reinterpret_cast<void*>(&TrackMappin), "Bool");
    track->AddParam("handle:gamemappinsMappinSystem", "system");
    track->AddParam("gameNewMappinID", "id");
    Commit(track);
}
} // namespace

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle, RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    if (aReason == RED4ext::v1::EMainReason::Load)
    {
        gSdk = aSdk;
        gPlugin = aHandle;
        auto rtti = RED4ext::CRTTISystem::Get();
        rtti->AddRegisterCallback(RegisterTypes);
        rtti->AddPostRegisterCallback(PostRegisterTypes);
        aSdk->scripts->Add(aHandle, L"Scripts");
        Log("OverlayMapNative loaded");
    }
    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"OverlayMapNative";
    aInfo->author = L"OverlayMap";
    aInfo->version = RED4EXT_V1_SEMVER(0, 1, 0);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_INDEPENDENT;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1_COMPAT_0; // older loaders reject "1"; v0 and v1 are ABI-compatible (photomode FINDINGS)
}
