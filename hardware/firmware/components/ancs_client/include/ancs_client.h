/*
 * ancs_client.h — NimBLE GATT client for the Apple Notification Center Service.
 *
 * After our peripheral accepts a connection from an iPhone, iOS exposes
 * ANCS on the same connection. This module discovers ANCS, subscribes
 * to the Notification Source and Data Source characteristics, and emits
 * a `ble_incoming_call_data_t` payload via the registered callback when
 * an incoming or missed call notification arrives.
 *
 * The callback is invoked from the NimBLE host task. Callers must do
 * their own locking when forwarding to LVGL.
 */
#ifndef ANCS_CLIENT_H
#define ANCS_CLIENT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ble_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ancs_client_call_cb_t)(const ble_incoming_call_data_t *data);

void ancs_client_init(ancs_client_call_cb_t on_call_event);

void ancs_client_start_for_connection(uint16_t conn_handle);

void ancs_client_handle_disconnect(uint16_t conn_handle);

bool ancs_client_handle_notification(uint16_t conn_handle, uint16_t attr_handle,
                                     const uint8_t *data, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* ANCS_CLIENT_H */
