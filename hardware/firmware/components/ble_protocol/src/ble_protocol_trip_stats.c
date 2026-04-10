/*
 * ble_protocol_trip_stats.c — trip stats body encoder/decoder.
 *
 * Wire layout (16 bytes, little-endian):
 *   offset  0..3 : uint32 ride_time_seconds
 *   offset  4..7 : uint32 distance_meters
 *   offset  8..9 : uint16 average_speed_kmh_x10   (0..=3000)
 *   offset 10..11: uint16 max_speed_kmh_x10       (0..=3000)
 *   offset 12..13: uint16 ascent_meters
 *   offset 14..15: uint16 descent_meters
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

static bool ble_trip_stats_in_range(const ble_trip_stats_data_t *in)
{
    if (in->average_speed_kmh_x10 > 3000U) {
        return false;
    }
    if (in->max_speed_kmh_x10 > 3000U) {
        return false;
    }
    return true;
}

ble_result_t ble_decode_trip_stats(const uint8_t *data, size_t length, uint8_t *out_flags,
                                   ble_trip_stats_data_t *out)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_TRIP_STATS) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_TRIP_STATS_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    const uint8_t *body = header.body;
    ble_trip_stats_data_t decoded;
    decoded.ride_time_seconds = ble_read_u32_le(&body[0]);
    decoded.distance_meters = ble_read_u32_le(&body[4]);
    decoded.average_speed_kmh_x10 = ble_read_u16_le(&body[8]);
    decoded.max_speed_kmh_x10 = ble_read_u16_le(&body[10]);
    decoded.ascent_meters = ble_read_u16_le(&body[12]);
    decoded.descent_meters = ble_read_u16_le(&body[14]);
    if (!ble_trip_stats_in_range(&decoded)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    *out = decoded;
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_trip_stats(const ble_trip_stats_data_t *in, uint8_t flags, uint8_t *out_buf,
                                   size_t out_cap, size_t *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_TRIP_STATS_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if (!ble_trip_stats_in_range(in)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0U) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    ble_write_header(out_buf, BLE_SCREEN_TRIP_STATS, flags,
                     (uint16_t)BLE_PROTOCOL_TRIP_STATS_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    ble_write_u32_le(&body[0], in->ride_time_seconds);
    ble_write_u32_le(&body[4], in->distance_meters);
    ble_write_u16_le(&body[8], in->average_speed_kmh_x10);
    ble_write_u16_le(&body[10], in->max_speed_kmh_x10);
    ble_write_u16_le(&body[12], in->ascent_meters);
    ble_write_u16_le(&body[14], in->descent_meters);
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_TRIP_STATS_BODY_SIZE;
    }
    return BLE_OK;
}
