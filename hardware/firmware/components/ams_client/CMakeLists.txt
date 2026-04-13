# ESP-IDF component registration for the Apple Media Service GATT client.
#
# The parser (src/ams_parser.c) is pure C and host-testable. The NimBLE
# wrapper (src/ams_client.c) is ESP-IDF only and links against bt + the
# ble_protocol codec to encode music payloads for the screen renderer.
if(CMAKE_PROJECT_NAME STREQUAL "scramscreen_host_tests")
    # Host build: parent CMakeLists adds the parser sources directly.
    return()
endif()

idf_component_register(
    SRCS
        "src/ams_parser.c"
        "src/ams_client.c"
    INCLUDE_DIRS
        "include"
    REQUIRES
        bt
        ble_protocol
)
