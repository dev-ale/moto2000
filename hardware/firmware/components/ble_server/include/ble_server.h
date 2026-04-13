/*
 * ble_server — NimBLE GATT server for the ScramScreen dashboard.
 *
 * Advertises the ScramScreen service and exposes three characteristics
 * (screen_data, control, status) matching docs/ble-protocol.md. Write
 * callbacks feed raw bytes into the ble_protocol / screen_fsm /
 * ble_reconnect components via the pure-C handlers in
 * ble_server_handlers.c.
 *
 * The public API is ESP-IDF-agnostic so app_main can call it without
 * leaking NimBLE types. The implementation (ble_server.c) is
 * ESP-IDF-only; ble_server_handlers.c is pure C and host-testable.
 */
#ifndef BLE_SERVER_H
#define BLE_SERVER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Application-level callbacks invoked from BLE context. Keep them short
 * or post to a queue — they run on the NimBLE host task. */
typedef void (*ble_server_screen_data_cb_t)(const uint8_t *payload, size_t len);
typedef void (*ble_server_control_cb_t)(const uint8_t *payload, size_t len);
typedef void (*ble_server_connection_cb_t)(bool connected);
typedef void (*ble_server_ota_data_cb_t)(const uint8_t *payload, size_t len);
/* Fired when the central enables notifications on the status
 * characteristic. The right place to send a one-shot announce
 * (firmware version, current screen, …) — sending earlier from
 * connect is racy because the central hasn't subscribed yet. */
typedef void (*ble_server_status_subscribed_cb_t)(void);

typedef struct {
    ble_server_screen_data_cb_t on_screen_data;
    ble_server_control_cb_t on_control;
    ble_server_connection_cb_t on_connection_change;
    ble_server_ota_data_cb_t on_ota_data;
    ble_server_status_subscribed_cb_t on_status_subscribed;
} ble_server_callbacks_t;

/* Initialise NimBLE and register the GATT service table.  Returns 0 on
 * success or a negative error code. */
int ble_server_init(const ble_server_callbacks_t *callbacks);

/* Start connectable advertising.  Call after init. */
int ble_server_start_advertising(void);

/* Stop advertising. */
int ble_server_stop_advertising(void);

/* Send a GATT notification on the status characteristic to the connected
 * central.  Returns 0 on success, negative on error. */
int ble_server_notify_status(const uint8_t *data, size_t len);

/* Returns true when a central is connected. */
bool ble_server_is_connected(void);

#ifdef __cplusplus
}
#endif

#endif /* BLE_SERVER_H */
