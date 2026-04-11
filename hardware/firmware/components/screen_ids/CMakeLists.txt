# ESP-IDF component registration. Header-only — no sources.
if(CMAKE_PROJECT_NAME STREQUAL "scramscreen_host_tests")
    return()
endif()

idf_component_register(
    INCLUDE_DIRS
        "include"
)
