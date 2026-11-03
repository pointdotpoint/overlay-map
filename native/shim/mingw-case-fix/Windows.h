// mingw shim: the vendored RED4ext.SDK includes <Windows.h> (capital W),
// matching MSVC's case-insensitive filesystem convention. The mingw-w64
// sysroot (/usr/x86_64-w64-mingw32/include) only ships lowercase
// windows.h, and Linux filesystems are case-sensitive, so the include
// fails outright under mingw. This one-line forwarding header, placed
// earlier on the include path than the mingw sysroot, resolves it without
// touching vendor/. See notes/FINDINGS.md Phase 3 for detail.
#include <windows.h>
