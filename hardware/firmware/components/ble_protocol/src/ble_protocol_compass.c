/*
 * ble_protocol_compass.c — compass body encoder/decoder.
 *
 * Wire layout (8 bytes, little-endian):
 *   offset 0..1 : uint16 magnetic_heading_deg_x10   (0..=3599)
 *   offset 2..3 : uint16 true_heading_deg_x10       (0..=3599, or 0xFFFF unknown)
 *   offset 4..5 : uint16 heading_accuracy_deg_x10   (0..=3599)
 *   offset 6    : uint8  compass_flags
 *                         bit 0 : use_true_heading
 *                         bits 1..7 : reserved, must be zero
 *   offset 7    : uint8  reserved                  (must be zero)
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

static bool ble_compass_in_range(const ble_compass_data_t *in)
{
    if (in->magnetic_heading_deg_x10 > 3599U) {
        return false;
    }
    if (in->true_heading_deg_x10 != BLE_COMPASS_TRUE_HEADING_UNKNOWN
        && in->true_heading_deg_x10 > 3599U) {
        return false;
    }
    if (in->heading_accuracy_deg_x10 > 3599U) {
        return false;
    }
    return true;
}

ble_result_t ble_decode_compass(const uint8_t      *data,
                                size_t              length,
                                uint8_t            *out_flags,
                                ble_compass_data_t *out_compass)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_COMPASS) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_COMPASS_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    const uint8_t     *body = header.body;
    ble_compass_data_t decoded;
    decoded.magnetic_heading_deg_x10 = ble_read_u16_le(&body[0]);
    decoded.true_heading_deg_x10     = ble_read_u16_le(&body[2]);
    decoded.heading_accuracy_deg_x10 = ble_read_u16_le(&body[4]);
    decoded.compass_flags            = body[6];
    const uint8_t reserved = body[7];
    if (reserved != 0U) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if ((decoded.compass_flags & BLE_COMPASS_FLAG_RESERVED_MASK) != 0U) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if (!ble_compass_in_range(&decoded)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    *out_compass = decoded;
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_compass(const ble_compass_data_t *in,
                                uint8_t                   flags,
                                uint8_t                  *out_buf,
                                size_t                    out_cap,
                                size_t                   *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_COMPASS_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if (!ble_compass_in_range(in)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    if ((in->compass_flags & BLE_COMPASS_FLAG_RESERVED_MASK) != 0U) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0U) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    ble_write_header(out_buf,
                     BLE_SCREEN_COMPASS,
                     flags,
                     (uint16_t)BLE_PROTOCOL_COMPASS_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    ble_write_u16_le(&body[0], in->magnetic_heading_deg_x10);
    ble_write_u16_le(&body[2], in->true_heading_deg_x10);
    ble_write_u16_le(&body[4], in->heading_accuracy_deg_x10);
    body[6] = in->compass_flags;
    body[7] = 0U;
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_COMPASS_BODY_SIZE;
    }
    return BLE_OK;
}
