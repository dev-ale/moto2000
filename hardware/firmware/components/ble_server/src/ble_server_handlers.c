/*
 * ble_server_handlers.c — pure-C dispatch, no ESP-IDF dependencies.
 *
 * Each function takes raw bytes from a BLE write callback and routes
 * them through the existing ble_protocol / screen_fsm / ble_reconnect
 * components.
 */

#include "ble_server_handlers.h"

#include "ble_protocol.h"
#include "ble_reconnect.h"
#include "screen_fsm.h"

#include <string.h>

/* ----------------------------------------------------------------------- */
/* screen_data writes                                                       */
/* ----------------------------------------------------------------------- */

void ble_server_handle_screen_data(const uint8_t *payload, size_t len, screen_fsm_t *fsm,
                                   ble_payload_cache_t *cache, uint32_t now_ms)
{
    if (!payload || !fsm || !cache) {
        return;
    }

    ble_header_t hdr;
    ble_result_t rc = ble_decode_header(payload, len, &hdr);
    if (rc != BLE_OK) {
        return; /* silently drop malformed packets */
    }

    uint8_t screen_id = (uint8_t)hdr.screen_id;

    /* Drive the screen FSM. */
    if (hdr.flags & BLE_FLAG_ALERT) {
        /* Alert overlays use the convenience wrapper which sets priority.
         * We use the screen_id as a simple priority value — higher
         * screen_ids are not inherently higher priority, but for the
         * two alert screens (incoming_call 0x09, blitzer 0x08) the
         * incoming call naturally wins. */
        screen_fsm_handle_alert(fsm, screen_id, screen_id);
    } else {
        screen_fsm_handle(fsm, SCREEN_FSM_EVT_DATA_ARRIVED, screen_id);
    }

    /* Cache the body for the render loop / staleness detection. */
    ble_payload_cache_store(cache, screen_id, hdr.body, (uint16_t)hdr.body_length, now_ms);
}

/* ----------------------------------------------------------------------- */
/* control writes                                                           */
/* ----------------------------------------------------------------------- */

void ble_server_handle_control(const uint8_t *payload, size_t len, screen_fsm_t *fsm)
{
    if (!payload || !fsm) {
        return;
    }

    ble_control_payload_t ctrl;
    ble_result_t rc = ble_decode_control(payload, len, &ctrl);
    if (rc != BLE_OK) {
        return; /* silently drop malformed control commands */
    }

    switch (ctrl.command) {
    case BLE_CONTROL_CMD_SET_ACTIVE_SCREEN:
        screen_fsm_handle(fsm, SCREEN_FSM_EVT_CONTROL_SET_ACTIVE, ctrl.screen_id);
        break;
    case BLE_CONTROL_CMD_SLEEP:
        screen_fsm_handle(fsm, SCREEN_FSM_EVT_CONTROL_SLEEP, 0);
        break;
    case BLE_CONTROL_CMD_WAKE:
        screen_fsm_handle(fsm, SCREEN_FSM_EVT_CONTROL_WAKE, 0);
        break;
    case BLE_CONTROL_CMD_CLEAR_ALERT:
        screen_fsm_handle(fsm, SCREEN_FSM_EVT_CONTROL_CLEAR_ALERT, 0);
        break;
    case BLE_CONTROL_CMD_SET_BRIGHTNESS:
        /* Brightness is handled by the display driver, not the FSM.
         * The app_main layer reads it via a separate path. */
        break;
    case BLE_CONTROL_CMD_CHECK_OTA_UPDATE:
        /* OTA check is handled by the OTA FSM, not the screen FSM. */
        break;
    case BLE_CONTROL_CMD_SET_SCREEN_ORDER:
        /* Screen order is persisted by the app_main layer. */
        break;
    }
}

/* ----------------------------------------------------------------------- */
/* connection state changes                                                 */
/* ----------------------------------------------------------------------- */

void ble_server_handle_connection_change(bool connected, ble_reconnect_fsm_t *reconnect_fsm,
                                         uint32_t now_ms)
{
    if (!reconnect_fsm) {
        return;
    }

    ble_reconnect_event_t evt = connected ? BLE_RC_EVENT_CONNECT : BLE_RC_EVENT_DISCONNECT;

    ble_reconnect_handle(reconnect_fsm, evt, now_ms);
}
