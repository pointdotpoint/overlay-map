// Pure byte-pattern helpers for finding engine internals from code the plugin can already locate (RTTI-registered
// functions, RED4ext's symbol-named address hashes). No engine or Windows dependency: host-tested by ResolveTest.cpp.
// Every finder returns 0 / -1 when the bytes don't match, so a game update turns the feature off instead of guessing.
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace nmn
{
// Offset of the first match of `aPattern` ("48 8D 0D ?? ?? ?? ??", hex bytes, ?? = any) in `aCode`, or -1.
inline std::ptrdiff_t Find(const uint8_t* aCode, std::size_t aSize, const char* aPattern)
{
    uint8_t bytes[128];
    bool any[128];
    std::size_t n = 0;
    for (const char* p = aPattern; *p && n < sizeof(bytes);)
    {
        if (*p == ' ')
        {
            ++p;
            continue;
        }
        if (p[0] == '?' && p[1] == '?')
        {
            any[n] = true;
            bytes[n++] = 0;
            p += 2;
            continue;
        }
        auto nibble = [](char c) -> int {
            if (c >= '0' && c <= '9')
                return c - '0';
            if (c >= 'a' && c <= 'f')
                return c - 'a' + 10;
            if (c >= 'A' && c <= 'F')
                return c - 'A' + 10;
            return -1;
        };
        int hi = nibble(p[0]), lo = p[1] ? nibble(p[1]) : -1;
        if (hi < 0 || lo < 0)
            return -1; // malformed pattern: never match
        any[n] = false;
        bytes[n++] = static_cast<uint8_t>(hi * 16 + lo);
        p += 2;
    }
    if (n == 0 || n > aSize)
        return -1;
    for (std::size_t i = 0; i + n <= aSize; ++i)
    {
        std::size_t k = 0;
        while (k < n && (any[k] || aCode[i + k] == bytes[k]))
            ++k;
        if (k == n)
            return static_cast<std::ptrdiff_t>(i);
    }
    return -1;
}

// Target of a RIP-relative operand: the instruction at `aInstrAddr` is `aInstrLen` bytes long and its disp32 sits at
// `aDispOffset` inside it.
inline uintptr_t RipTarget(uintptr_t aInstrAddr, const uint8_t* aInstr, int aDispOffset, int aInstrLen)
{
    int32_t disp;
    std::memcpy(&disp, aInstr + aDispOffset, sizeof(disp));
    return aInstrAddr + static_cast<uintptr_t>(aInstrLen) + static_cast<uintptr_t>(static_cast<intptr_t>(disp));
}

// rtti::NativeGlobalFunction ctor (game 2.5): stores the native body into an inline handler array, indexed by the
// function's regIndex (written at +0xF0):
//   lea rcx, [table]; mov eax, [counter]; lea edx, [rax+0xFF]; inc eax; mov [counter], eax; mov rax, rbx;
//   mov [rbx+0xF0], edx; mov rbx, [rsp+30h]; mov [rcx+rdx*8], rdi
inline constexpr const char* kHandlerTablePattern = "48 8D 0D ?? ?? ?? ?? 8B 05 ?? ?? ?? ?? 8D 90 FF 00 00 00 FF C0 "
                                                    "89 05 ?? ?? ?? ?? 48 8B C3 89 93 F0 00 00 00 48 8B 5C 24 30 "
                                                    "48 89 3C D1";
// Before game 2.5 CBaseFunction was 0x40 bytes smaller, so regIndex sat at +0xB0.
inline constexpr const char* kHandlerTablePatternPre25 = "48 8D 0D ?? ?? ?? ?? 8B 05 ?? ?? ?? ?? 8D 90 FF 00 00 00 FF C0 "
                                                         "89 05 ?? ?? ?? ?? 48 8B C3 89 93 B0 00 00 00 48 8B 5C 24 30 "
                                                         "48 89 3C D1";

// Address of the native handler table, read from the ctor's code (`aCtor` = its first `aSize` bytes, loaded at
// `aCtorAddr`). 0 if the pattern isn't there.
inline uintptr_t HandlerTableFromCtor(const uint8_t* aCtor, std::size_t aSize, uintptr_t aCtorAddr)
{
    auto at = Find(aCtor, aSize, kHandlerTablePattern);
    if (at < 0)
        at = Find(aCtor, aSize, kHandlerTablePatternPre25);
    if (at < 0)
        return 0;
    return RipTarget(aCtorAddr + static_cast<uintptr_t>(at), aCtor + at, 3, 7);
}

// WorldMapMenuGameController.TrackMappin native body: reads the controller handle into [rsp+20h], then
//   lea rdx, [rsp+20h]; mov rcx, rdi; call internal
inline constexpr const char* kTrackBodyPattern = "48 8D 54 24 20 48 8B CF E8 ?? ?? ?? ??";

inline uintptr_t TrackInternalFromBody(const uint8_t* aBody, std::size_t aSize, uintptr_t aBodyAddr)
{
    auto at = Find(aBody, aSize, kTrackBodyPattern);
    if (at < 0)
        return 0;
    return RipTarget(aBodyAddr + static_cast<uintptr_t>(at) + 8, aBody + at + 8, 1, 5);
}

// The internal resolves the mappin from the controller and calls the mappin system:
//   test rdx, rdx; je untrack; mov rdx, [rdx+idOffset]; call [rax+track]; jmp end; untrack: call [rax+untrack]
inline constexpr const char* kTrackSlotsPattern = "48 85 D2 74 ?? 48 8B 52 ?? FF 90 ?? ?? ?? ?? EB ?? FF 90 ?? ?? ?? ??";

struct TrackSlots
{
    bool ok = false;
    uint32_t track = 0;   // MappinSystem vtable byte offset: track(this, NewMappinID)
    uint32_t untrack = 0; // MappinSystem vtable byte offset: untrack(this)
    uint8_t idOffset = 0; // IMappin field holding its NewMappinID
};

inline TrackSlots SlotsFromTrackInternal(const uint8_t* aCode, std::size_t aSize)
{
    TrackSlots slots;
    auto at = Find(aCode, aSize, kTrackSlotsPattern);
    if (at < 0)
        return slots;
    std::memcpy(&slots.track, aCode + at + 11, 4);
    std::memcpy(&slots.untrack, aCode + at + 19, 4);
    slots.idOffset = aCode[at + 8];
    // Plausible vtable slots only: 8-aligned, adjacent (untrack follows track), inside a sane vtable.
    slots.ok = slots.track % 8 == 0 && slots.untrack == slots.track + 8 && slots.track < 0x1000;
    return slots;
}

// A native thunk `inc qword [rdx]; jmp target` (skip ParamEnd, tail-call the implementation): its target, or 0.
inline uintptr_t JumpTargetOfThunk(const uint8_t* aBody, std::size_t aSize, uintptr_t aBodyAddr)
{
    if (aSize < 8 || Find(aBody, 8, "48 FF 02 E9 ?? ?? ?? ??") != 0)
        return 0;
    return RipTarget(aBodyAddr + 3, aBody + 3, 1, 5);
}
} // namespace nmn
