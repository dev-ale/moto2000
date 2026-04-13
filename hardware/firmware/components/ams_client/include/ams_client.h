/*
 * ams_client.h — NimBLE GATT client for the Apple Media Service.
 *
 * After our peripheral accepts a connection from an iPhone, iOS exposes
 * its own GATT server on the same connection — including the Apple
 * Media Service. This module discovers AMS, subscribes to track and
 * playback updates, and emits a fully-formed `ble_music_data_t` payload
 * via the registered callback whenever something changes.
 *
 * The callback is invoked from the NimBLE host task, NOT from a render
 * task. Callers must be ready to do their own locking when forwarding
 * to LVGL.
 */
#ifndef AMS_CLIENT_H
#define AMS_CLIENT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ble_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Callback fired whenever the AMS client receives a fresh attribute
 * update. `data` is a snapshot of the current track + playback state
 * with all known fields populated.
 */
typedef void (*ams_client_track_cb_t)(const ble_music_data_t *data);

/*
 * Initialise the AMS client. Must be called once before
 * ams_client_start_for_connection().
 */
void ams_client_init(ams_client_track_cb_t on_track_update);

/*
 * Begin the GATT client discovery + subscription state machine for the
 * given iOS connection. Call this from the BLE_GAP_EVENT_CONNECT handler
 * after a phone connects to our peripheral.
 *
 * Discovery is asynchronous; the callback will fire when AMS pushes its
 * first update.
 */
void ams_client_start_for_connection(uint16_t conn_handle);

/*
 * Drop all per-connection state. Call this from BLE_GAP_EVENT_DISCONNECT.
 */
void ams_client_handle_disconnect(uint16_t conn_handle);

/*
 * Forward a NimBLE notification (BLE_GAP_EVENT_NOTIFY_RX) to the AMS
 * client. Returns true if the notification was for an AMS characteristic
 * and was consumed; false if the caller should keep dispatching.
 */
bool ams_client_handle_notification(uint16_t conn_handle, uint16_t attr_handle, const uint8_t *data,
                                    size_t len);

#ifdef __cplusplus
}
#endif

#endif /* AMS_CLIENT_H */
