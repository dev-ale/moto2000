/*
 * ble_protocol_lean_angle.c — lean angle body encoder/decoder.
 *
 * Wire layout (8 bytes, little-endian):
 *   offset 0..1 : int16  current_lean_deg_x10    (-900..=900)
 *                          negative = left lean, positive = right lean
 *   offset 2..3 : uint16 max_left_lean_deg_x10   (0..=900)  unsigned magnitude
 *   offset 4..5 : uint16 max_right_lean_deg_x10  (0..=900)
 *   offset 6    : uint8  confidence_percent      (0..=100)
 *   offset 7    : uint8  reserved                (must be zero)
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

static bool ble_lean_angle_in_range(const ble_lean_angle_data_t *in)
{
    if (in->current_lean_deg_x10 < -BLE_LEAN_ANGLE_MAX_ABS_X10 ||
        in->current_lean_deg_x10 > BLE_LEAN_ANGLE_MAX_ABS_X10) {
        return false;
    }
    if (in->max_left_lean_deg_x10 > (uint16_t)BLE_LEAN_ANGLE_MAX_ABS_X10) {
        return false;
    }
    if (in->max_right_lean_deg_x10 > (uint16_t)BLE_LEAN_ANGLE_MAX_ABS_X10) {
        return false;
    }
    if (in->confidence_percent > 100U) {
        return false;
    }
    return true;
}

ble_result_t ble_decode_lean_angle(const uint8_t *data, size_t length, uint8_t *out_flags,
                                   ble_lean_angle_data_t *out)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_LEAN_ANGLE) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_LEAN_ANGLE_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    const uint8_t *body = header.body;
    ble_lean_angle_data_t decoded;
    decoded.current_lean_deg_x10 = ble_read_i16_le(&body[0]);
    decoded.max_left_lean_deg_x10 = ble_read_u16_le(&body[2]);
    decoded.max_right_lean_deg_x10 = ble_read_u16_le(&body[4]);
    decoded.confidence_percent = body[6];
    const uint8_t reserved = body[7];
    if (reserved != 0U) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if (!ble_lean_angle_in_range(&decoded)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    *out = decoded;
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_lean_angle(const ble_lean_angle_data_t *in, uint8_t flags, uint8_t *out_buf,
                                   size_t out_cap, size_t *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_LEAN_ANGLE_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if (!ble_lean_angle_in_range(in)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0U) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    ble_write_header(out_buf, BLE_SCREEN_LEAN_ANGLE, flags,
                     (uint16_t)BLE_PROTOCOL_LEAN_ANGLE_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    ble_write_i16_le(&body[0], in->current_lean_deg_x10);
    ble_write_u16_le(&body[2], in->max_left_lean_deg_x10);
    ble_write_u16_le(&body[4], in->max_right_lean_deg_x10);
    body[6] = in->confidence_percent;
    body[7] = 0U;
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_LEAN_ANGLE_BODY_SIZE;
    }
    return BLE_OK;
}
