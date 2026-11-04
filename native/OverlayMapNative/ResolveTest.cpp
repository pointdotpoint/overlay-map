// Host test for Resolve.hpp (g++ on Linux): the matcher finds the handler table in the recorded 2.5 ctor bytes and
// refuses them after one changed byte. Run: tools/native/test.sh
#include "Resolve.hpp"
#include "ResolveFixtures.hpp"

#include <cstdio>
#include <cstring>
#include <vector>

namespace
{
// rtti::NativeGlobalFunction::NativeGlobalFunction, game 2.5 (3.0.88.46235), at 0x140b488f8.
const uint8_t kCtor[] = {
    0x48, 0x89, 0x5c, 0x24, 0x08, 0x57, 0x48, 0x83, 0xec, 0x20, 0x49, 0x8b, 0xf9, 0x48, 0x8b, 0xd9,
    0x41, 0xb9, 0x03, 0x00, 0x00, 0x00, 0xe8, 0x51, 0x4c, 0xb7, 0xff, 0x48, 0x8d, 0x05, 0x8e, 0xb0,
    0x57, 0x02, 0x48, 0x89, 0x03, 0x48, 0x8d, 0x0d, 0x0c, 0x34, 0xff, 0x02, 0x8b, 0x05, 0x06, 0x34,
    0x07, 0x03, 0x8d, 0x90, 0xff, 0x00, 0x00, 0x00, 0xff, 0xc0, 0x89, 0x05, 0xf8, 0x33, 0x07, 0x03,
    0x48, 0x8b, 0xc3, 0x89, 0x93, 0xf0, 0x00, 0x00, 0x00, 0x48, 0x8b, 0x5c, 0x24, 0x30, 0x48, 0x89,
    0x3c, 0xd1, 0x48, 0x83, 0xc4, 0x20, 0x5f, 0xc3};
const uintptr_t kCtorAddr = 0x140b488f8;
const uintptr_t kTable = 0x143b3bd30;

int failures = 0;

void Check(bool aOk, const char* aName)
{
    std::printf("%s %s\n", aOk ? "PASS" : "FAIL", aName);
    if (!aOk)
        ++failures;
}
} // namespace

int main()
{
    Check(nmn::Find(kCtor, sizeof(kCtor), "48 8D 0D ?? ?? ?? ?? 8B 05") == 0x25, "find with wildcards");
    Check(nmn::Find(kCtor, sizeof(kCtor), "DE AD") == -1, "find refuses absent bytes");
    Check(nmn::Find(kCtor, 4, "48 89 5C 24 08") == -1, "find stays inside the buffer");

    Check(nmn::HandlerTableFromCtor(kCtor, sizeof(kCtor), kCtorAddr) == kTable, "handler table from 2.5 ctor");

    for (size_t i : {0x26u, 0x34u, 0x45u, 0x51u}) // opcode bytes inside the pattern
    {
        std::vector<uint8_t> changed(kCtor, kCtor + sizeof(kCtor));
        changed[i] ^= 0x01;
        char name[64];
        std::snprintf(name, sizeof(name), "refuses a changed byte at 0x%zx", i);
        Check(nmn::HandlerTableFromCtor(changed.data(), changed.size(), kCtorAddr) == 0, name);
    }

    // The matched lea's displacement may change between builds: only the target moves.
    {
        std::vector<uint8_t> moved(kCtor, kCtor + sizeof(kCtor));
        moved[0x28] += 0x10;
        Check(nmn::HandlerTableFromCtor(moved.data(), moved.size(), kCtorAddr) == kTable + 0x10,
              "follows a moved displacement");
    }

    // WorldMapMenuGameController.TrackMappin's native body → its internal; the internal → MappinSystem slots.
    Check(nmn::TrackInternalFromBody(fixture::kTrackBody, sizeof(fixture::kTrackBody), 0x142d5ca28) == 0x142d5913c,
          "track internal from the TrackMappin body");
    {
        auto slots = nmn::SlotsFromTrackInternal(fixture::kTrackInternal, sizeof(fixture::kTrackInternal));
        Check(slots.ok && slots.track == 0x220 && slots.untrack == 0x228 && slots.idOffset == 0x40,
              "track/untrack slots and id offset from the internal");
        std::vector<uint8_t> changed(fixture::kTrackInternal, fixture::kTrackInternal + sizeof(fixture::kTrackInternal));
        changed[0x110] ^= 0x01; // the first "FF 90" of call [rax+0x220]
        Check(!nmn::SlotsFromTrackInternal(changed.data(), changed.size()).ok, "slots refuse a changed call opcode");
    }
    Check(nmn::JumpTargetOfThunk(fixture::kSysUntrackBody, sizeof(fixture::kSysUntrackBody), 0x142212870) ==
              0x142d44a20,
          "MappinSystem.UntrackMappin thunk target");
    {
        uint8_t notThunk[8] = {0x48, 0x89, 0x5c, 0x24, 0x08, 0x57, 0x48, 0x83};
        Check(nmn::JumpTargetOfThunk(notThunk, sizeof(notThunk), 0x1000) == 0, "thunk refuses other code");
    }

    // WorldMapMenuGameController.TrackCustomPositionMappin: thunk → internal → the custom-waypoint register block.
    Check(nmn::JumpTargetOfThunk(fixture::kCustomBody, sizeof(fixture::kCustomBody), 0x142d5ca20) == 0x142d5a27c,
          "TrackCustomPositionMappin thunk target");

    std::printf("%d failure(s)\n", failures);
    return failures ? 1 : 0;
}
