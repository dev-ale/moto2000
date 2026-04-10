# ble_server component — NimBLE GATT server for the ScramScreen dashboard.
#
# On the host-test build only the handlers are compiled (they are
# pulled in directly by the test CMakeLists). The NimBLE code requires
# the ESP-IDF BT stack.

if(CMAKE_PROJECT_NAME STREQUAL "scramscreen_host_tests")
    return()  # host builds use only the handlers, not the NimBLE code
endif()

idf_component_register(
    SRCS "src/ble_server.c" "src/ble_server_handlers.c"
    INCLUDE_DIRS "include"
    PRIV_INCLUDE_DIRS "src"
    REQUIRES bt ble_protocol screen_fsm ble_reconnect
)
