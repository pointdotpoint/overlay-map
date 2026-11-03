// mingw shim: force-included (via -include) ahead of every TU that
// touches RED4ext.SDK headers. Combines two independent compat fixes into
// one header so CMake only needs a single -include flag (multiple
// `-include X -include Y` entries passed through target_compile_options
// got flattened into one `-include X Y` by CMake's list handling, which
// gcc/g++ rejects as "multiple files" -- see notes/FINDINGS.md Phase 3).
#pragma once

// 1) RED4ext.SDK uses MSVC's __declspec(align(N)) throughout (Quaternion,
//    Vector4-family types, etc.). mingw's g++ recognizes __declspec but
//    silently ignores the "align" spelling (GCC's equivalent attribute is
//    "aligned"), which misaligns every struct built on top of those types
//    and cascades into RED4EXT_ASSERT_OFFSET/SIZE failures throughout
//    Rendering/ and Scripting/Natives/.
//
//    A naive `#define align(x) aligned(x)` + `#define __declspec(x)
//    __attribute__((x))` works in isolation but poisons the bare
//    identifier `align`, which collides with std::align (<memory>,
//    pulled in transitively by RED4ext.SDK's own Buffer/JobQueue/etc
//    headers) -- "macro 'align' passed 4 arguments, but takes just 1".
//
//    Instead, paste __declspec's argument onto a private prefix and
//    dispatch only known spellings, so unrelated identifiers are never
//    touched. The spelling list covers every __declspec form used by the
//    vendored SDK (align, dllexport -- verified with
//    `grep -rhoE '__declspec\([a-zA-Z_]+' include/ src/`) plus every form
//    mingw's own windows.h/_mingw*.h headers rely on internally (verified
//    the same way against /usr/x86_64-w64-mingw32/include/), so GCC's
//    native (working) __declspec handling for those is fully replaced,
//    not shadowed.
#ifdef __MINGW32__
#define __declspec(x) RED4EXT_DECLSPEC_(x)
#define RED4EXT_DECLSPEC_(x) RED4EXT_DECLSPEC_##x
#define RED4EXT_DECLSPEC_align(n) __attribute__((aligned(n)))
#define RED4EXT_DECLSPEC_dllexport __attribute__((dllexport))
#define RED4EXT_DECLSPEC_dllimport __attribute__((dllimport))
#define RED4EXT_DECLSPEC_deprecated __attribute__((deprecated))
#define RED4EXT_DECLSPEC_noreturn __attribute__((noreturn))
#define RED4EXT_DECLSPEC_nothrow __attribute__((nothrow))
#define RED4EXT_DECLSPEC_noalias
#define RED4EXT_DECLSPEC_restrict __attribute__((__malloc__))
#endif

// 2) Several SDK headers use std::forward/move/invoke, std::memcpy/memset/
//    memmove, and sqrtf without including <utility>/<functional>/
//    <cstring>/<cmath>. MSVC's STL headers pull these in transitively
//    through other includes; libstdc++ does not, so mingw builds fail
//    with "is not a member of 'std'".
#include <utility>
#include <functional>
#include <cstring>
#include <cmath>

// 3) SpinLock-inl.hpp / SharedSpinLock-inl.hpp call the MSVC 8-bit
//    interlocked intrinsics InterlockedExchange8 and
//    _InterlockedExchangeAdd8. mingw-w64's <intrin.h> implements the
//    32/64-bit forms (and even _InterlockedCompareExchange8) but not
//    these two 8-bit ones. Provide them via GCC's __atomic builtins,
//    matching MSVC's documented semantics (return the *previous* value).
#ifdef __MINGW32__
#include <intrin.h>
static __forceinline char InterlockedExchange8(char volatile* aTarget, char aValue)
{
    return __atomic_exchange_n(aTarget, aValue, __ATOMIC_SEQ_CST);
}
static __forceinline char _InterlockedExchangeAdd8(char volatile* aAddend, char aValue)
{
    return __atomic_fetch_add(aAddend, aValue, __ATOMIC_SEQ_CST);
}
#endif
