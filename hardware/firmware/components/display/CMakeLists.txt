# display component -- ESP-IDF component registration.
#
# For host builds (project name "scramscreen_host_tests") the parent
# CMakeLists adds the sources directly, so we bail out here.
if(CMAKE_PROJECT_NAME STREQUAL "scramscreen_host_tests")
    return()
endif()

idf_component_register(
    SRCS
        "src/display_common.c"
        "src/display_waveshare.c"
    INCLUDE_DIRS
        "include"
    PRIV_INCLUDE_DIRS
        "src"
    REQUIRES
        esp_lcd lvgl driver
)
