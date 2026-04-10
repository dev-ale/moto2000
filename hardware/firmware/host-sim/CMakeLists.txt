# ScramScreen host simulator.
#
# A standalone (non-ESP-IDF) CMake project that builds on macOS and Linux.
# It links the ble_protocol C library from hardware/firmware/components/
# and uses LVGL v9 to render ScramScreen screens into an offscreen RGB
# buffer, which is written out as a PNG for snapshot testing.
#
# This target is intentionally headless: no SDL window, no runtime network,
# fully deterministic so CI can run it on ubuntu-latest.
#
# Usage:
#   cmake -S hardware/firmware/host-sim -B hardware/firmware/host-sim/build
#   cmake --build hardware/firmware/host-sim/build
#   ctest --test-dir hardware/firmware/host-sim/build --output-on-failure
#
# Run directly:
#   scramscreen-host-sim --out /tmp/clock.png < protocol/fixtures/valid/clock_basel_winter.bin
#
# Input format on stdin: raw BLE payload bytes (the same bytes a BLE peer
# would write to the firmware characteristic). The simulator reads until
# EOF and treats everything read as a single payload.

cmake_minimum_required(VERSION 3.16)
project(scramscreen_host_sim C)

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

include(FetchContent)

# ---------------------------------------------------------------------------
# stb single-header libraries (PNG read + PNG write).
# Public domain. Vendored via FetchContent so contributors do not need to
# copy files around; the fetch happens once at configure time.
# ---------------------------------------------------------------------------
FetchContent_Declare(
    stb
    GIT_REPOSITORY https://github.com/nothings/stb.git
    GIT_TAG        f0569113c93ad095470c54bf34a17b36646bbbb5 # pinned for reproducibility
)
FetchContent_MakeAvailable(stb)

add_library(stb_image STATIC src/stb_impl.c)
target_include_directories(stb_image PUBLIC "${stb_SOURCE_DIR}")
# stb is third-party; it does not pass our paranoid flags.
target_compile_options(stb_image PRIVATE
    -w
)

# ---------------------------------------------------------------------------
# ble_protocol as a host-buildable static library.
# Same reuse trick as hardware/firmware/test/host/CMakeLists.txt.
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
)
target_include_directories(ble_protocol
    PUBLIC  "${BLE_PROTOCOL_ROOT}/include"
    PRIVATE "${BLE_PROTOCOL_ROOT}/src"
)

# ---------------------------------------------------------------------------
# scramscreen-host-sim executable.
# ---------------------------------------------------------------------------
add_executable(scramscreen-host-sim
    src/main.c
    src/renderer.c
    src/screen_clock.c
    src/screen_compass.c
    src/screen_speed.c
    src/screen_navigation.c
    src/screen_trip_stats.c
    src/screen_weather.c
    src/screen_lean_angle.c
    src/screen_placeholder.c
    src/compass_layout.c
    src/lean_angle_layout.c
    src/speed_layout.c
    src/trip_stats_layout.c
    src/weather_layout.c
    src/png_writer.c
    src/text_draw.c
    src/time_format.c
    src/navigation_layout.c
    src/screen_music.c
    src/music_layout.c
    src/screen_appointment.c
    src/appointment_layout.c
)
target_include_directories(scramscreen-host-sim PRIVATE include)
target_link_libraries(scramscreen-host-sim PRIVATE ble_protocol stb_image m)

# ---------------------------------------------------------------------------
# Snapshot diff helper (separate tiny C executable).
# ---------------------------------------------------------------------------
add_executable(snapshot-diff tests/snapshot_diff.c)
target_link_libraries(snapshot-diff PRIVATE stb_image)

# ---------------------------------------------------------------------------
# Snapshot tests.
# Each test: run the simulator against a fixture → PNG → diff against golden.
# ---------------------------------------------------------------------------
get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
set(FIXTURES_DIR  "${REPO_ROOT}/protocol/fixtures/valid")
set(SNAPSHOTS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/snapshots")

function(add_snapshot_test name fixture)
    add_test(
        NAME snapshot_${name}
        COMMAND ${CMAKE_COMMAND}
            -DSIM=$<TARGET_FILE:scramscreen-host-sim>
            -DDIFF=$<TARGET_FILE:snapshot-diff>
            -DFIXTURE=${FIXTURES_DIR}/${fixture}
            -DGOLDEN=${SNAPSHOTS_DIR}/${name}.png
            -DOUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/snapshot-out
            -DNAME=${name}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/run_snapshot_test.cmake
    )
endfunction()

add_snapshot_test(clock_basel_winter             clock_basel_winter.bin)
add_snapshot_test(clock_night_mode               clock_night_mode.bin)
add_snapshot_test(compass_north_magnetic         compass_north_magnetic.bin)
add_snapshot_test(compass_east_true              compass_east_true.bin)
add_snapshot_test(compass_southwest_unknown_true compass_southwest_unknown_true.bin)
add_snapshot_test(speed_urban_45kmh              speed_urban_45kmh.bin)
add_snapshot_test(speed_highway_120kmh           speed_highway_120kmh.bin)
add_snapshot_test(speed_stationary               speed_stationary.bin)
add_snapshot_test(nav_straight                   nav_straight.bin)
add_snapshot_test(nav_sharp_left                 nav_sharp_left.bin)
add_snapshot_test(nav_arrive                     nav_arrive.bin)
add_snapshot_test(trip_stats_fresh                trip_stats_fresh.bin)
add_snapshot_test(trip_stats_city_loop            trip_stats_city_loop.bin)
add_snapshot_test(trip_stats_highway              trip_stats_highway.bin)
add_snapshot_test(weather_basel_clear             weather_basel_clear.bin)
add_snapshot_test(weather_alps_snow               weather_alps_snow.bin)
add_snapshot_test(weather_paris_rain              weather_paris_rain.bin)
add_snapshot_test(weather_cold_fog                weather_cold_fog.bin)
add_snapshot_test(weather_thunderstorm            weather_thunderstorm.bin)
add_snapshot_test(lean_upright                    lean_upright.bin)
add_snapshot_test(lean_moderate_right             lean_moderate_right.bin)
add_snapshot_test(lean_hard_left                  lean_hard_left.bin)
add_snapshot_test(lean_racetrack                  lean_racetrack.bin)
add_snapshot_test(music_playing                  music_playing.bin)
add_snapshot_test(music_paused                   music_paused.bin)
add_snapshot_test(music_long_titles              music_long_titles.bin)
add_snapshot_test(music_unknown_duration         music_unknown_duration.bin)
add_snapshot_test(appointment_soon               appointment_soon.bin)
add_snapshot_test(appointment_now                appointment_now.bin)
add_snapshot_test(appointment_past               appointment_past.bin)

# ---------------------------------------------------------------------------
# Unity host tests for pure C logic inside the simulator (time formatting).
# ---------------------------------------------------------------------------
FetchContent_Declare(
    unity
    GIT_REPOSITORY https://github.com/ThrowTheSwitch/Unity.git
    GIT_TAG        v2.6.0
)
FetchContent_MakeAvailable(unity)

add_executable(test_host_sim_logic
    tests/test_time_format.c
    src/time_format.c
)
target_include_directories(test_host_sim_logic PRIVATE include)
target_link_libraries(test_host_sim_logic PRIVATE unity)
add_test(NAME host_sim_logic COMMAND test_host_sim_logic)

add_executable(test_compass_layout
    tests/test_compass_layout.c
    src/compass_layout.c
)
target_include_directories(test_compass_layout PRIVATE include src)
target_link_libraries(test_compass_layout PRIVATE unity ble_protocol)
target_link_libraries(test_compass_layout PRIVATE m)
add_test(NAME compass_layout COMMAND test_compass_layout)

add_executable(test_speed_layout
    tests/test_speed_layout.c
    src/speed_layout.c
)
target_include_directories(test_speed_layout PRIVATE include)
target_link_libraries(test_speed_layout PRIVATE unity m)
add_test(NAME speed_layout COMMAND test_speed_layout)

add_executable(test_lean_angle_layout
    tests/test_lean_angle_layout.c
    src/lean_angle_layout.c
)
target_include_directories(test_lean_angle_layout PRIVATE include src)
target_link_libraries(test_lean_angle_layout PRIVATE unity m)
add_test(NAME lean_angle_layout COMMAND test_lean_angle_layout)

add_executable(test_host_sim_navigation_layout
    tests/test_navigation_layout.c
    src/navigation_layout.c
)
target_include_directories(test_host_sim_navigation_layout PRIVATE include)
target_link_libraries(test_host_sim_navigation_layout PRIVATE unity ble_protocol)
add_test(NAME host_sim_navigation_layout
         COMMAND test_host_sim_navigation_layout)

add_executable(test_trip_stats_layout
    tests/test_trip_stats_layout.c
    src/trip_stats_layout.c
)
target_include_directories(test_trip_stats_layout PRIVATE include)
target_link_libraries(test_trip_stats_layout PRIVATE unity)
add_test(NAME trip_stats_layout COMMAND test_trip_stats_layout)

add_executable(test_weather_layout
    tests/test_weather_layout.c
    src/weather_layout.c
)
target_include_directories(test_weather_layout PRIVATE include src)
target_link_libraries(test_weather_layout PRIVATE unity ble_protocol)
add_test(NAME weather_layout COMMAND test_weather_layout)

add_executable(test_music_layout
    tests/test_music_layout.c
    src/music_layout.c
)
target_include_directories(test_music_layout PRIVATE include)
target_link_libraries(test_music_layout PRIVATE unity)
add_test(NAME music_layout COMMAND test_music_layout)

add_executable(test_appointment_layout
    tests/test_appointment_layout.c
    src/appointment_layout.c
)
target_include_directories(test_appointment_layout PRIVATE include)
target_link_libraries(test_appointment_layout PRIVATE unity)
add_test(NAME appointment_layout COMMAND test_appointment_layout)
