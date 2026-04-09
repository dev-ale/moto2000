# Host-side Unity tests for ScramScreen firmware components.
#
# This project builds on plain Linux/macOS with no ESP-IDF toolchain. It is
# invoked by CI on ubuntu-latest to run unit tests for any firmware logic that
# can be compiled for the host (protocol codecs, FSMs, pure C helpers).
#
# Usage:
#   cd hardware/firmware/test/host
#   cmake -B build
#   cmake --build build
#   ctest --test-dir build --output-on-failure

cmake_minimum_required(VERSION 3.16)
project(scramscreen_host_tests C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()

add_compile_options(
    -Wall
    -Wextra
    -Wpedantic
    -Werror
    -Wshadow
    -Wformat=2
    -Wconversion
    -Wno-unused-parameter
)

enable_testing()

# Fetch Unity via FetchContent so contributors don't need to vendor it.
include(FetchContent)
FetchContent_Declare(
    unity
    GIT_REPOSITORY https://github.com/ThrowTheSwitch/Unity.git
    GIT_TAG        v2.6.0
)
FetchContent_MakeAvailable(unity)

add_executable(test_smoke test_smoke.c)
target_link_libraries(test_smoke PRIVATE unity)
add_test(NAME smoke COMMAND test_smoke)
