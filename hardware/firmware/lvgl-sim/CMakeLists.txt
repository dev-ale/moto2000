# ScramScreen LVGL simulator.
#
# A standalone CMake project that renders the 466x466 round AMOLED display
# in an SDL2 window on macOS (and Linux). Unlike host-sim which uses a
# bitmap-font software rasteriser for CI snapshots, this project uses real
# LVGL v9 with anti-aliased fonts, smooth arcs, and proper styling — the
# same C code that will flash to the ESP32 unchanged.
#
# Prerequisites:
#   brew install sdl2 cmake    (macOS)
#   apt install libsdl2-dev    (Linux)
#
# Usage:
#   cmake -S hardware/firmware/lvgl-sim -B hardware/firmware/lvgl-sim/build
#   cmake --build hardware/firmware/lvgl-sim/build
#   ./hardware/firmware/lvgl-sim/build/scramscreen-lvgl-sim \
#       --in protocol/fixtures/valid/clock_basel_winter.bin
#   ./hardware/firmware/lvgl-sim/build/scramscreen-lvgl-sim --live

cmake_minimum_required(VERSION 3.16)
project(scramscreen_lvgl_sim C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()

# Strict warnings for our code; LVGL headers may trigger some, handled below.
add_compile_options(
    -Wall
    -Wextra
    -Wpedantic
    -Wno-unused-parameter
)

include(FetchContent)

# ---------------------------------------------------------------------------
# LVGL v9.2 via FetchContent.
# ---------------------------------------------------------------------------
FetchContent_Declare(
    lvgl
    GIT_REPOSITORY https://github.com/lvgl/lvgl.git
    GIT_TAG        v9.2.2
)
FetchContent_MakeAvailable(lvgl)

# Point LVGL at our lv_conf.h (must be visible before LVGL's own headers).
target_compile_definitions(lvgl PUBLIC LV_CONF_PATH=${CMAKE_CURRENT_SOURCE_DIR}/lv_conf.h)
target_include_directories(lvgl PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

# Suppress warnings in LVGL's own sources.
target_compile_options(lvgl PRIVATE -w)

# ---------------------------------------------------------------------------
# SDL2.
# ---------------------------------------------------------------------------
find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL2 REQUIRED sdl2)

# LVGL's built-in SDL driver needs the SDL2 headers at compile time.
target_include_directories(lvgl PUBLIC ${SDL2_INCLUDE_DIRS})
target_link_libraries(lvgl PUBLIC ${SDL2_LIBRARIES})
target_link_directories(lvgl PUBLIC ${SDL2_LIBRARY_DIRS})

# ---------------------------------------------------------------------------
# ble_protocol — same reuse trick as host-sim/CMakeLists.txt.
# ---------------------------------------------------------------------------
set(BLE_PROTOCOL_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../components/ble_protocol")
add_library(ble_protocol STATIC
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_clock.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_nav.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_speed_heading.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_compass.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_trip_stats.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_weather.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_lean_angle.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_music.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_appointment.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_fuel.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_altitude.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_call.c"
    "${BLE_PROTOCOL_ROOT}/src/ble_protocol_blitzer.c"
)
target_include_directories(ble_protocol
    PUBLIC  "${BLE_PROTOCOL_ROOT}/include"
    PRIVATE "${BLE_PROTOCOL_ROOT}/src"
)

# ---------------------------------------------------------------------------
# scramscreen-lvgl-sim executable.
# ---------------------------------------------------------------------------
add_executable(scramscreen-lvgl-sim
    main.c
    theme/scram_theme.c
    screens/screen_clock.c
    screens/screen_placeholder.c
    common/screen_manager.c
)
target_include_directories(scramscreen-lvgl-sim PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${SDL2_INCLUDE_DIRS}
)
target_link_libraries(scramscreen-lvgl-sim PRIVATE
    lvgl
    ${SDL2_LIBRARIES}
    ble_protocol
)
target_link_directories(scramscreen-lvgl-sim PRIVATE ${SDL2_LIBRARY_DIRS})
