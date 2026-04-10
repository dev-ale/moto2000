/*
 * ble_protocol_appointment.c — appointment body encoder/decoder.
 *
 * Wire format (60 bytes) defined in docs/ble-protocol.md:
 *
 *   offset 0  : int16   starts_in_minutes (-1440..=10080)
 *   offset 2  : char[32] title  (UTF-8, null-terminated, <=31 bytes)
 *   offset 34 : char[24] location (UTF-8, null-terminated, <=23 bytes)
 *   offset 58 : uint16  reserved (must be 0)
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <string.h>

#define APPOINTMENT_TITLE_LEN    ((size_t)32)
#define APPOINTMENT_LOCATION_LEN ((size_t)24)

#define APPOINTMENT_TITLE_OFFSET    ((size_t)2)
#define APPOINTMENT_LOCATION_OFFSET ((size_t)34)
#define APPOINTMENT_RESERVED_OFFSET ((size_t)58)

static bool field_is_terminated(const uint8_t *field, size_t len)
{
    for (size_t i = 0; i < len; ++i) {
        if (field[i] == 0) {
            return true;
        }
    }
    return false;
}

ble_result_t ble_decode_appointment(const uint8_t *data, size_t length, uint8_t *out_flags,
                                    ble_appointment_data_t *out)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_APPOINTMENT) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_APPOINTMENT_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }

    const uint8_t *body = header.body;
    const int16_t minutes = ble_read_i16_le(&body[0]);
    if (minutes < BLE_APPOINTMENT_MIN_STARTS_IN_MINUTES ||
        minutes > BLE_APPOINTMENT_MAX_STARTS_IN_MINUTES) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    if (!field_is_terminated(&body[APPOINTMENT_TITLE_OFFSET], APPOINTMENT_TITLE_LEN)) {
        return BLE_ERR_UNTERMINATED_STRING;
    }
    if (!field_is_terminated(&body[APPOINTMENT_LOCATION_OFFSET], APPOINTMENT_LOCATION_LEN)) {
        return BLE_ERR_UNTERMINATED_STRING;
    }

    const uint16_t reserved = ble_read_u16_le(&body[APPOINTMENT_RESERVED_OFFSET]);
    if (reserved != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }

    out->starts_in_minutes = minutes;
    memset(out->title, 0, sizeof(out->title));
    memcpy(out->title, &body[APPOINTMENT_TITLE_OFFSET], APPOINTMENT_TITLE_LEN);
    memset(out->location, 0, sizeof(out->location));
    memcpy(out->location, &body[APPOINTMENT_LOCATION_OFFSET], APPOINTMENT_LOCATION_LEN);
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_appointment(const ble_appointment_data_t *in, uint8_t flags,
                                    uint8_t *out_buf, size_t out_cap, size_t *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_APPOINTMENT_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    if (in->starts_in_minutes < BLE_APPOINTMENT_MIN_STARTS_IN_MINUTES ||
        in->starts_in_minutes > BLE_APPOINTMENT_MAX_STARTS_IN_MINUTES) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    const size_t title_len = ble_strnlen(in->title, APPOINTMENT_TITLE_LEN);
    const size_t location_len = ble_strnlen(in->location, APPOINTMENT_LOCATION_LEN);
    if (title_len >= APPOINTMENT_TITLE_LEN || location_len >= APPOINTMENT_LOCATION_LEN) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    ble_write_header(out_buf, BLE_SCREEN_APPOINTMENT, flags,
                     (uint16_t)BLE_PROTOCOL_APPOINTMENT_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    ble_write_i16_le(&body[0], in->starts_in_minutes);
    memset(&body[APPOINTMENT_TITLE_OFFSET], 0, APPOINTMENT_TITLE_LEN);
    memcpy(&body[APPOINTMENT_TITLE_OFFSET], in->title, title_len);
    memset(&body[APPOINTMENT_LOCATION_OFFSET], 0, APPOINTMENT_LOCATION_LEN);
    memcpy(&body[APPOINTMENT_LOCATION_OFFSET], in->location, location_len);
    ble_write_u16_le(&body[APPOINTMENT_RESERVED_OFFSET], 0);
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_APPOINTMENT_BODY_SIZE;
    }
    return BLE_OK;
}
