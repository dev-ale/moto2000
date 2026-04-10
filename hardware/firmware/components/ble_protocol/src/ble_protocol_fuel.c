/*
 * ble_protocol_fuel.c — fuel estimate body encoder/decoder.
 *
 * Wire layout (little-endian, 8 bytes total):
 *   offset 0     : uint8  tank_percent          (0..100)
 *   offset 1     : uint8  reserved              (must be 0)
 *   offset 2..3  : uint16 estimated_range_km    (0xFFFF = unknown)
 *   offset 4..5  : uint16 consumption_ml_per_km (0xFFFF = unknown)
 *   offset 6..7  : uint16 fuel_remaining_ml     (0xFFFF = unknown)
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <string.h>

ble_result_t ble_decode_fuel(const uint8_t      *data,
                             size_t              length,
                             uint8_t            *out_flags,
                             ble_fuel_data_t    *out)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_FUEL_ESTIMATE) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_FUEL_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    const uint8_t *body     = header.body;
    const uint8_t  pct      = body[0];
    const uint8_t  reserved = body[1];
    if (reserved != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if (pct > 100) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    out->tank_percent          = pct;
    out->estimated_range_km    = ble_read_u16_le(&body[2]);
    out->consumption_ml_per_km = ble_read_u16_le(&body[4]);
    out->fuel_remaining_ml     = ble_read_u16_le(&body[6]);
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_fuel(const ble_fuel_data_t *in,
                             uint8_t                flags,
                             uint8_t               *out_buf,
                             size_t                 out_cap,
                             size_t                *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_FUEL_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    if (in->tank_percent > 100) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    ble_write_header(out_buf, BLE_SCREEN_FUEL_ESTIMATE, flags,
                     (uint16_t)BLE_PROTOCOL_FUEL_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    body[0] = in->tank_percent;
    body[1] = 0; /* reserved */
    ble_write_u16_le(&body[2], in->estimated_range_km);
    ble_write_u16_le(&body[4], in->consumption_ml_per_km);
    ble_write_u16_le(&body[6], in->fuel_remaining_ml);
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_FUEL_BODY_SIZE;
    }
    return BLE_OK;
}
