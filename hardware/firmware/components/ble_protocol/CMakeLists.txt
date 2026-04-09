# ESP-IDF component registration.
#
# The ble_protocol component is pure C and has no ESP-IDF dependencies so the
# same sources can be compiled by the host-test harness under
# `hardware/firmware/test/host/` with a plain CMake target.
if(CMAKE_PROJECT_NAME STREQUAL "scramscreen_host_tests")
    # Host build: parent CMakeLists adds the sources directly.
    return()
endif()

idf_component_register(
    SRCS
        "src/ble_protocol.c"
        "src/ble_protocol_clock.c"
        "src/ble_protocol_nav.c"
        "src/ble_protocol_speed_heading.c"
        "src/ble_protocol_compass.c"
        "src/ble_protocol_control.c"
        "src/ble_protocol_trip_stats.c"
        "src/ble_protocol_weather.c"
    INCLUDE_DIRS
        "include"
    PRIV_INCLUDE_DIRS
        "src"
    REQUIRES
)
