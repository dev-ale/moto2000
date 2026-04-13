/*
 * ble_protocol_status.c — status characteristic encoder/decoder.
 *
 * Wire format (variable size, minimum 3 bytes):
 *
 *   byte 0: protocol version (0x01)
 *   byte 1: status type (see ble_status_type_t)
 *   byte 2+: type-specific payload
 *
 * Currently the only status type is SCREEN_CHANGED (0x01) which carries
 * a single screen_id byte at offset 2.
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <string.h>

ble_result_t ble_encode_status(const ble_status_payload_t *in, uint8_t *out_buf, size_t out_cap,
                               size_t *out_written)
{
    if (in == NULL || out_buf == NULL) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    switch (in->type) {
    case BLE_STATUS_SCREEN_CHANGED:
        if (out_cap < BLE_STATUS_PAYLOAD_MIN_SIZE) {
            return BLE_ERR_BUFFER_TOO_SMALL;
        }
        if (!ble_is_known_screen(in->screen_id)) {
            return BLE_ERR_UNKNOWN_SCREEN_ID;
        }
        out_buf[0] = BLE_PROTOCOL_VERSION;
        out_buf[1] = (uint8_t)BLE_STATUS_SCREEN_CHANGED;
        out_buf[2] = in->screen_id;
        if (out_written != NULL) {
            *out_written = BLE_STATUS_PAYLOAD_MIN_SIZE;
        }
        return BLE_OK;
    case BLE_STATUS_FIRMWARE_VERSION:
        if (out_cap < 5) {
            return BLE_ERR_BUFFER_TOO_SMALL;
        }
        out_buf[0] = BLE_PROTOCOL_VERSION;
        out_buf[1] = (uint8_t)BLE_STATUS_FIRMWARE_VERSION;
        out_buf[2] = in->fw_major;
        out_buf[3] = in->fw_minor;
        out_buf[4] = in->fw_patch;
        if (out_written != NULL) {
            *out_written = 5;
        }
        return BLE_OK;
    default:
        return BLE_ERR_UNKNOWN_STATUS_TYPE;
    }
}

ble_result_t ble_decode_status(const uint8_t *data, size_t length,
                               ble_status_payload_t *out_payload)
{
    if (data == NULL || out_payload == NULL) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if (length < BLE_STATUS_PAYLOAD_MIN_SIZE) {
        return BLE_ERR_TRUNCATED_HEADER;
    }
    if (data[0] != BLE_PROTOCOL_VERSION) {
        return BLE_ERR_UNSUPPORTED_VERSION;
    }
    const uint8_t type = data[1];

    memset(out_payload, 0, sizeof(*out_payload));

    switch (type) {
    case BLE_STATUS_SCREEN_CHANGED:
        if (!ble_is_known_screen(data[2])) {
            return BLE_ERR_UNKNOWN_SCREEN_ID;
        }
        out_payload->type = BLE_STATUS_SCREEN_CHANGED;
        out_payload->screen_id = data[2];
        return BLE_OK;
    case BLE_STATUS_FIRMWARE_VERSION:
        if (length < 5) {
            return BLE_ERR_TRUNCATED_HEADER;
        }
        out_payload->type = BLE_STATUS_FIRMWARE_VERSION;
        out_payload->fw_major = data[2];
        out_payload->fw_minor = data[3];
        out_payload->fw_patch = data[4];
        return BLE_OK;
    default:
        return BLE_ERR_UNKNOWN_STATUS_TYPE;
    }
}
