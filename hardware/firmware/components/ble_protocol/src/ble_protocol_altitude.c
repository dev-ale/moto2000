/*
 * ble_protocol_altitude.c — altitude profile body encoder/decoder.
 *
 * Wire layout (little-endian, 128 bytes total):
 *   offset 0..1   : int16  current_altitude_m       (-500..=9000)
 *   offset 2..3   : uint16 total_ascent_m
 *   offset 4..5   : uint16 total_descent_m
 *   offset 6      : uint8  sample_count             (0..=60)
 *   offset 7      : uint8  reserved                 (must be 0)
 *   offset 8..127 : int16[60] profile               altitude samples in meters
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <string.h>

ble_result_t ble_decode_altitude(const uint8_t *data, size_t length, uint8_t *out_flags,
                                 ble_altitude_profile_data_t *out)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_ALTITUDE) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_ALTITUDE_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    const uint8_t *body = header.body;
    const int16_t cur_alt = ble_read_i16_le(&body[0]);
    const uint16_t ascent = ble_read_u16_le(&body[2]);
    const uint16_t descent = ble_read_u16_le(&body[4]);
    const uint8_t count = body[6];
    const uint8_t reserved = body[7];
    if (reserved != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if (count > BLE_ALTITUDE_MAX_SAMPLES) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    if (cur_alt < BLE_ALTITUDE_MIN_M || cur_alt > BLE_ALTITUDE_MAX_M) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    out->current_altitude_m = cur_alt;
    out->total_ascent_m = ascent;
    out->total_descent_m = descent;
    out->sample_count = count;
    for (int i = 0; i < BLE_ALTITUDE_MAX_SAMPLES; ++i) {
        out->profile[i] = ble_read_i16_le(&body[8 + (size_t)i * 2U]);
    }
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_altitude(const ble_altitude_profile_data_t *in, uint8_t flags,
                                 uint8_t *out_buf, size_t out_cap, size_t *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_ALTITUDE_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    if (in->sample_count > BLE_ALTITUDE_MAX_SAMPLES) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    if (in->current_altitude_m < BLE_ALTITUDE_MIN_M ||
        in->current_altitude_m > BLE_ALTITUDE_MAX_M) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    ble_write_header(out_buf, BLE_SCREEN_ALTITUDE, flags,
                     (uint16_t)BLE_PROTOCOL_ALTITUDE_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    ble_write_i16_le(&body[0], in->current_altitude_m);
    ble_write_u16_le(&body[2], in->total_ascent_m);
    ble_write_u16_le(&body[4], in->total_descent_m);
    body[6] = in->sample_count;
    body[7] = 0; /* reserved */
    for (int i = 0; i < BLE_ALTITUDE_MAX_SAMPLES; ++i) {
        ble_write_i16_le(&body[8 + (size_t)i * 2U], in->profile[i]);
    }
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_ALTITUDE_BODY_SIZE;
    }
    return BLE_OK;
}
