# ESP-IDF component registration.
#
# ble_reconnect is pure C with no ESP-IDF dependencies so the same sources
# can be compiled by the host-test harness under hardware/firmware/test/host/
# with a plain CMake target. The host build adds them directly.
if(CMAKE_PROJECT_NAME STREQUAL "scramscreen_host_tests")
    return()
endif()

idf_component_register(
    SRCS
        "src/ble_reconnect.c"
    INCLUDE_DIRS
        "include"
    REQUIRES
        screen_ids
)
