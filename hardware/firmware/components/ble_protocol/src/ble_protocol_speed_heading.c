/*
 * ble_protocol_speed_heading.c — speedHeading body encoder/decoder.
 *
 * Wire layout (8 bytes, little-endian):
 *   offset 0..1 : uint16 speed_kmh_x10        (0..=3000)
 *   offset 2..3 : uint16 heading_deg_x10      (0..=3599)
 *   offset 4..5 : int16  altitude_m           (-500..=9000)
 *   offset 6..7 : int16  temperature_celsius_x10 (-500..=600)
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

static bool ble_speed_heading_in_range(const ble_speed_heading_data_t *in)
{
    if (in->speed_kmh_x10 > 3000U) {
        return false;
    }
    if (in->heading_deg_x10 > 3599U) {
        return false;
    }
    if (in->altitude_m < -500 || in->altitude_m > 9000) {
        return false;
    }
    if (in->temperature_celsius_x10 < -500 || in->temperature_celsius_x10 > 600) {
        return false;
    }
    return true;
}

ble_result_t ble_decode_speed_heading(const uint8_t            *data,
                                      size_t                    length,
                                      uint8_t                  *out_flags,
                                      ble_speed_heading_data_t *out)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_SPEED_HEADING) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_SPEED_HEADING_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    const uint8_t *body = header.body;
    ble_speed_heading_data_t decoded;
    decoded.speed_kmh_x10           = ble_read_u16_le(&body[0]);
    decoded.heading_deg_x10         = ble_read_u16_le(&body[2]);
    decoded.altitude_m              = ble_read_i16_le(&body[4]);
    decoded.temperature_celsius_x10 = ble_read_i16_le(&body[6]);
    if (!ble_speed_heading_in_range(&decoded)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    *out = decoded;
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_speed_heading(const ble_speed_heading_data_t *in,
                                      uint8_t                         flags,
                                      uint8_t                        *out_buf,
                                      size_t                          out_cap,
                                      size_t                         *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_SPEED_HEADING_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if (!ble_speed_heading_in_range(in)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    ble_write_header(out_buf,
                     BLE_SCREEN_SPEED_HEADING,
                     flags,
                     (uint16_t)BLE_PROTOCOL_SPEED_HEADING_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    ble_write_u16_le(&body[0], in->speed_kmh_x10);
    ble_write_u16_le(&body[2], in->heading_deg_x10);
    ble_write_i16_le(&body[4], in->altitude_m);
    ble_write_i16_le(&body[6], in->temperature_celsius_x10);
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_SPEED_HEADING_BODY_SIZE;
    }
    return BLE_OK;
}
