/*
 * ble_protocol_control.c — control characteristic encoder/decoder.
 *
 * Wire format (4 bytes total):
 *
 *   byte 0: protocol version (0x01)
 *   byte 1: command id (see ble_control_command_t)
 *   byte 2: value byte 0 (command-specific)
 *   byte 3: value byte 1 (command-specific, zero for commands < 2 bytes)
 *
 * Commands without value bytes (sleep, wake, clearAlert) require both
 * trailing bytes to be zero. Decoders reject non-zero reserved bytes.
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <string.h>

ble_result_t ble_encode_control(const ble_control_payload_t *in, uint8_t *out_buf, size_t out_cap,
                                size_t *out_written)
{
    if (in == NULL || out_buf == NULL) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    /* Variable-length command: setScreenOrder. */
    if (in->command == BLE_CONTROL_CMD_SET_SCREEN_ORDER) {
        if (in->screen_order_count > BLE_CONTROL_MAX_SCREEN_ORDER) {
            return BLE_ERR_INVALID_COMMAND_VALUE;
        }
        const size_t needed = 3u + in->screen_order_count;
        if (out_cap < needed) {
            return BLE_ERR_BUFFER_TOO_SMALL;
        }
        out_buf[0] = BLE_PROTOCOL_VERSION;
        out_buf[1] = (uint8_t)BLE_CONTROL_CMD_SET_SCREEN_ORDER;
        out_buf[2] = in->screen_order_count;
        for (uint8_t i = 0; i < in->screen_order_count; ++i) {
            if (!ble_is_known_screen(in->screen_order[i])) {
                return BLE_ERR_UNKNOWN_SCREEN_ID;
            }
            out_buf[3 + i] = in->screen_order[i];
        }
        if (out_written != NULL) {
            *out_written = needed;
        }
        return BLE_OK;
    }

    /* Fixed-size commands. */
    if (out_cap < BLE_CONTROL_PAYLOAD_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    out_buf[0] = BLE_PROTOCOL_VERSION;
    out_buf[1] = (uint8_t)in->command;
    out_buf[2] = 0;
    out_buf[3] = 0;
    switch (in->command) {
    case BLE_CONTROL_CMD_SET_ACTIVE_SCREEN:
        if (!ble_is_known_screen(in->screen_id)) {
            return BLE_ERR_UNKNOWN_SCREEN_ID;
        }
        out_buf[2] = in->screen_id;
        break;
    case BLE_CONTROL_CMD_SET_BRIGHTNESS:
        if (in->brightness > 100u) {
            return BLE_ERR_INVALID_COMMAND_VALUE;
        }
        out_buf[2] = in->brightness;
        break;
    case BLE_CONTROL_CMD_SLEEP:
    case BLE_CONTROL_CMD_WAKE:
    case BLE_CONTROL_CMD_CLEAR_ALERT:
    case BLE_CONTROL_CMD_CHECK_OTA_UPDATE:
        /* No value bytes; already zeroed. */
        break;
    default:
        return BLE_ERR_UNKNOWN_COMMAND;
    }
    if (out_written != NULL) {
        *out_written = BLE_CONTROL_PAYLOAD_SIZE;
    }
    return BLE_OK;
}

ble_result_t ble_decode_control(const uint8_t *data, size_t length,
                                ble_control_payload_t *out_payload)
{
    if (data == NULL || out_payload == NULL) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if (length < 2) {
        return BLE_ERR_TRUNCATED_HEADER;
    }
    if (data[0] != BLE_PROTOCOL_VERSION) {
        return BLE_ERR_UNSUPPORTED_VERSION;
    }
    const uint8_t cmd = data[1];

    memset(out_payload, 0, sizeof(*out_payload));

    /* Variable-length command: setScreenOrder. */
    if (cmd == BLE_CONTROL_CMD_SET_SCREEN_ORDER) {
        if (length < 3) {
            return BLE_ERR_TRUNCATED_HEADER;
        }
        const uint8_t count = data[2];
        if (count > BLE_CONTROL_MAX_SCREEN_ORDER) {
            return BLE_ERR_INVALID_COMMAND_VALUE;
        }
        if (length < 3u + count) {
            return BLE_ERR_TRUNCATED_BODY;
        }
        out_payload->command = BLE_CONTROL_CMD_SET_SCREEN_ORDER;
        out_payload->screen_order_count = count;
        for (uint8_t i = 0; i < count; ++i) {
            if (!ble_is_known_screen(data[3 + i])) {
                return BLE_ERR_UNKNOWN_SCREEN_ID;
            }
            out_payload->screen_order[i] = data[3 + i];
        }
        return BLE_OK;
    }

    /* Fixed-size commands require exactly 4 bytes. */
    if (length < BLE_CONTROL_PAYLOAD_SIZE) {
        return BLE_ERR_TRUNCATED_HEADER;
    }
    const uint8_t value0 = data[2];
    const uint8_t value1 = data[3];

    switch (cmd) {
    case BLE_CONTROL_CMD_SET_ACTIVE_SCREEN:
        if (value1 != 0) {
            return BLE_ERR_INVALID_RESERVED;
        }
        if (!ble_is_known_screen(value0)) {
            return BLE_ERR_UNKNOWN_SCREEN_ID;
        }
        out_payload->command = BLE_CONTROL_CMD_SET_ACTIVE_SCREEN;
        out_payload->screen_id = value0;
        return BLE_OK;
    case BLE_CONTROL_CMD_SET_BRIGHTNESS:
        if (value1 != 0) {
            return BLE_ERR_INVALID_RESERVED;
        }
        if (value0 > 100u) {
            return BLE_ERR_INVALID_COMMAND_VALUE;
        }
        out_payload->command = BLE_CONTROL_CMD_SET_BRIGHTNESS;
        out_payload->brightness = value0;
        return BLE_OK;
    case BLE_CONTROL_CMD_SLEEP:
    case BLE_CONTROL_CMD_WAKE:
    case BLE_CONTROL_CMD_CLEAR_ALERT:
    case BLE_CONTROL_CMD_CHECK_OTA_UPDATE:
        if (value0 != 0 || value1 != 0) {
            return BLE_ERR_INVALID_RESERVED;
        }
        out_payload->command = (ble_control_command_t)cmd;
        return BLE_OK;
    default:
        return BLE_ERR_UNKNOWN_COMMAND;
    }
}
