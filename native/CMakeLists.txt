cmake_minimum_required(VERSION 3.24)
project(OverlayMapNative CXX)
# C++23: RED4ext.SDK's DynArray.hpp needs a C++23 constexpr relaxation under GCC (see the photomode plugin's FINDINGS).
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Game 2.5 changed engine layouts (Callback buffer 64, CBaseFunction +0x40): needs an SDK with 2.5 support.
set(RED4EXT_SDK "${CMAKE_SOURCE_DIR}/vendor/RED4ext.SDK" CACHE PATH "RED4ext.SDK checkout (2.5 support)")

if(MINGW)
  # mingw-w64 only ships lowercase windows.h and drops __declspec(align); shims copied from the photomode plugin.
  include_directories(BEFORE ${CMAKE_SOURCE_DIR}/shim/mingw-case-fix)
endif()

add_subdirectory(${RED4EXT_SDK} ${CMAKE_BINARY_DIR}/red4ext-sdk)

if(MINGW)
  get_target_property(_red4ext_sdk_sources RED4ext.SDK SOURCES)
  list(FILTER _red4ext_sdk_sources EXCLUDE REGEX "/src/(GpuApi|Rendering)/|/src/Scripting/Natives\\.cpp$")
  set_target_properties(RED4ext.SDK PROPERTIES SOURCES "${_red4ext_sdk_sources}")
  target_compile_options(RED4ext.SDK PRIVATE -include ${CMAKE_SOURCE_DIR}/shim/mingw-case-fix/mingw-compat.hpp)
endif()

add_library(OverlayMapNative SHARED OverlayMapNative/Main.cpp)
set_target_properties(OverlayMapNative PROPERTIES PREFIX "" SUFFIX ".dll")
target_link_libraries(OverlayMapNative PRIVATE RED4ext::SDK)
if(MINGW)
  # -s strips debug info (the static C++ runtime carries ~13 MB of it); the export table stays.
  target_link_options(OverlayMapNative PRIVATE -static-libgcc -static-libstdc++ -static -s)
  target_compile_options(OverlayMapNative PRIVATE -include ${CMAKE_SOURCE_DIR}/shim/mingw-case-fix/mingw-compat.hpp)
endif()
