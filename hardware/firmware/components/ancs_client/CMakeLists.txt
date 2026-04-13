# ESP-IDF component registration for the Apple Notification Center Service
# GATT client.
#
# The parser (src/ancs_parser.c) is pure C and host-testable. The NimBLE
# wrapper (src/ancs_client.c) is ESP-IDF only.
if(CMAKE_PROJECT_NAME STREQUAL "scramscreen_host_tests")
    return()
endif()

idf_component_register(
    SRCS
        "src/ancs_parser.c"
        "src/ancs_client.c"
    INCLUDE_DIRS
        "include"
    REQUIRES
        bt
        ble_protocol
)
