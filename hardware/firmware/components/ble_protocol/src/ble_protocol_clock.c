/*
 * ble_protocol_clock.c — clock body encoder/decoder.
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <string.h>

static bool ble_clock_timezone_in_range(int16_t tz)
{
    return tz >= -720 && tz <= 840;
}

ble_result_t ble_decode_clock(const uint8_t    *data,
                              size_t            length,
                              uint8_t          *out_flags,
                              ble_clock_data_t *out_clock)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_CLOCK) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_CLOCK_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    const uint8_t *body      = header.body;
    const int64_t  unix_time = ble_read_i64_le(&body[0]);
    const int16_t  tz        = (int16_t)ble_read_u16_le(&body[8]);
    const uint8_t  flags_b   = body[10];
    const uint8_t  reserved  = body[11];
    if (reserved != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if ((flags_b & 0xFEU) != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if (!ble_clock_timezone_in_range(tz)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    out_clock->unix_time         = unix_time;
    out_clock->tz_offset_minutes = tz;
    out_clock->is_24h            = (flags_b & 0x01U) != 0;
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_clock(const ble_clock_data_t *clock,
                              uint8_t                 flags,
                              uint8_t                *out_buf,
                              size_t                  out_cap,
                              size_t                 *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_CLOCK_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if (!ble_clock_timezone_in_range(clock->tz_offset_minutes)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    ble_write_header(out_buf, BLE_SCREEN_CLOCK, flags, (uint16_t)BLE_PROTOCOL_CLOCK_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    ble_write_i64_le(&body[0], clock->unix_time);
    ble_write_i16_le(&body[8], clock->tz_offset_minutes);
    body[10] = (uint8_t)(clock->is_24h ? 0x01 : 0x00);
    body[11] = 0;
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_CLOCK_BODY_SIZE;
    }
    return BLE_OK;
}
