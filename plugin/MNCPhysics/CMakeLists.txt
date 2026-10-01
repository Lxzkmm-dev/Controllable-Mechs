# MNC Physics: Mechs of Night City's optional RED4ext plugin (see src/Main.cpp).
# Build (Visual Studio 2022/2026 with C++, CMake 3.21+):
#   cmake -S . -B build -G "Visual Studio 18 2026" -A x64 -DRED4EXT_SDK_DIR=<RED4ext.SDK checkout>
#   cmake --build build --config Release
# The DLL goes to red4ext/plugins/MNCPhysics/ with the scripts/ folder beside it.
cmake_minimum_required(VERSION 3.21)
project(MNCPhysics LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(RED4EXT_SDK_DIR "" CACHE PATH "A checkout of github.com/WopsS/RED4ext.SDK")
if(NOT RED4EXT_SDK_DIR)
  message(FATAL_ERROR "Set RED4EXT_SDK_DIR to a RED4ext.SDK checkout")
endif()
set(RED4EXT_HEADER_ONLY ON CACHE BOOL "" FORCE)
add_subdirectory(${RED4EXT_SDK_DIR} red4ext_sdk EXCLUDE_FROM_ALL)

# PhysX 3.4 public headers (BSD-3), only for the virtual interfaces of the game's own PhysX
# DLLs; nothing is linked (PxGetPhysics is looked up at runtime)
set(PHYSX34_DIR "" CACHE PATH "PhysX 3.4 headers (with PhysX_3.4/Include and PxShared/include)")
if(NOT PHYSX34_DIR)
  message(FATAL_ERROR "Set PHYSX34_DIR to the PhysX 3.4 headers")
endif()

add_library(MNCPhysics SHARED src/Main.cpp src/PhysXBody.cpp)
target_include_directories(MNCPhysics SYSTEM PRIVATE "${PHYSX34_DIR}/PhysX_3.4/Include" "${PHYSX34_DIR}/PxShared/include")
target_link_libraries(MNCPhysics PRIVATE RED4ext::SDK)
target_compile_definitions(MNCPhysics PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
if(MSVC)
  target_compile_options(MNCPhysics PRIVATE /W3 /utf-8)
endif()
