# ESP-IDF component registration.
#
# ota_fsm is pure C with no ESP-IDF dependencies so the same sources
# can be compiled by the host-test harness under hardware/firmware/test/host/
# with a plain CMake target. The host build adds them directly.
if(CMAKE_PROJECT_NAME STREQUAL "scramscreen_host_tests")
    return()
endif()

idf_component_register(
    SRCS
        "src/ota_fsm.c"
        "src/ota_version.c"
        "src/ota_verify.c"
        "vendor/sha256.c"
    INCLUDE_DIRS
        "include"
        "vendor"
    REQUIRES
)
