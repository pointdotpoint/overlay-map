#!/usr/bin/env bash
# Cross-compile the optional OverlayMapNative RED4ext plugin and stage it as it ships:
#   dist-native/red4ext/plugins/OverlayMapNative/{OverlayMapNative.dll, Scripts/OverlayMapNative.reds}
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$HERE/.scratch/native-build"
OUT="$HERE/dist-native/red4ext/plugins/OverlayMapNative"
cmake -S "$HERE/native" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$HERE/native/cmake/mingw-w64.cmake" ${RED4EXT_SDK:+-DRED4EXT_SDK="$RED4EXT_SDK"} >/dev/null
cmake --build "$BUILD" 2>&1 | tail -20
rm -rf "$OUT"   # stale .reds would ship otherwise
mkdir -p "$OUT/Scripts"
cp "$BUILD/OverlayMapNative.dll" "$OUT/"
cp "$HERE"/native/OverlayMapNative/*.reds "$OUT/Scripts/"
echo "built $OUT"
