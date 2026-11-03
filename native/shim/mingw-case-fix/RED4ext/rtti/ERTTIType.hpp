// mingw case-fix shim: the SDK's own headers include this file as
// "RED4ext/rtti/ERTTIType.hpp" (lowercase rtti) while the real file lives
// at RED4ext/RTTI/ERTTIType.hpp (uppercase). MSVC's case-insensitive
// filesystem hides this; mingw on a case-sensitive Linux filesystem does
// not. See notes/FINDINGS.md Phase 3.
#include <RED4ext/RTTI/ERTTIType.hpp>
