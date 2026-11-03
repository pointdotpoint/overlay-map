#!/usr/bin/env bash
# Host-compile and run the NightMapNative unit tests (pure code only; no engine).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$HERE/.scratch/native-test"
mkdir -p "$OUT"
g++ -std=c++20 -Wall -Wextra -O1 -o "$OUT/resolve_test" "$HERE/native/NightMapNative/ResolveTest.cpp"
"$OUT/resolve_test"
