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

# ------------------------------------------------------------------------- #
# ble_protocol as a host-buildable static library                            #
# ------------------------------------------------------------------------- #
#
# The sources under hardware/firmware/components/ble_protocol are plain C
# with no ESP-IDF dependencies, so we compile them here for the host.
set(BLE_PROTOCOL_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../components/ble_protocol")
add_library(ble_protocol STATIC
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_clock.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_nav.c"
)
target_include_directories(ble_protocol
    PUBLIC "${BLE_PROTOCOL_ROOT}/include"
    PRIVATE "${BLE_PROTOCOL_ROOT}/src"
)

# Shared fixture directory is at the repo root.
get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../.." ABSOLUTE)
set(FIXTURES_DIR "${REPO_ROOT}/protocol/fixtures")

# ------------------------------------------------------------------------- #
# Tests                                                                      #
# ------------------------------------------------------------------------- #

add_executable(test_smoke test_smoke.c)
target_link_libraries(test_smoke PRIVATE unity)
add_test(NAME smoke COMMAND test_smoke)

add_executable(test_ble_protocol test_ble_protocol.c)
target_link_libraries(test_ble_protocol PRIVATE unity ble_protocol)
target_compile_definitions(test_ble_protocol
    PRIVATE "SCRAMSCREEN_FIXTURES_DIR=\"${FIXTURES_DIR}\""
)
add_test(NAME ble_protocol COMMAND test_ble_protocol)
