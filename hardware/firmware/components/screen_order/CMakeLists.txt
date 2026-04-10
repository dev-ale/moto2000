# ESP-IDF component registration. Pure C with no IDF deps so it also
# compiles under the host-test harness.
if(CMAKE_PROJECT_NAME STREQUAL "scramscreen_host_tests")
    return()
endif()

idf_component_register(
    SRCS
        "src/screen_order.c"
    INCLUDE_DIRS
        "include"
    REQUIRES
)
