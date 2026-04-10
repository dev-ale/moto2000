/*
 * ble_server_handlers — pure-C dispatch layer between the BLE write
 * callbacks and the existing firmware components.
 *
 * This file has ZERO ESP-IDF or NimBLE dependencies. It is compiled on
 * the host and tested via Unity.
 */
#ifndef BLE_SERVER_HANDLERS_H
#define BLE_SERVER_HANDLERS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ble_reconnect.h"
#include "screen_fsm.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Called when the central writes to the screen_data characteristic.
 * Decodes the header, drives the screen FSM, and stores the body in
 * the payload cache.
 */
void ble_server_handle_screen_data(const uint8_t *payload, size_t len,
                                   screen_fsm_t *fsm,
                                   ble_payload_cache_t *cache,
                                   uint32_t now_ms);

/*
 * Called when the central writes to the control characteristic.
 * Decodes the control command and maps it to screen FSM events.
 */
void ble_server_handle_control(const uint8_t *payload, size_t len,
                               screen_fsm_t *fsm);

/*
 * Called on BLE connect/disconnect. Drives the reconnect FSM.
 */
void ble_server_handle_connection_change(bool connected,
                                         ble_reconnect_fsm_t *reconnect_fsm,
                                         uint32_t now_ms);

#ifdef __cplusplus
}
#endif

#endif /* BLE_SERVER_HANDLERS_H */
