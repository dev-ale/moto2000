/*
 * ble_protocol_nav.c — navigation body encoder/decoder.
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <string.h>

#define STREET_NAME_FIELD_LEN ((size_t)32)

static bool ble_nav_ranges_ok(int32_t lat, int32_t lng, uint16_t speed_x10, uint16_t heading_x10)
{
    if (lat < -900000000 || lat > 900000000) {
        return false;
    }
    if (lng < -1800000000 || lng > 1800000000) {
        return false;
    }
    if (speed_x10 > 3000) {
        return false;
    }
    if (heading_x10 > 3599) {
        return false;
    }
    return true;
}

static bool ble_maneuver_is_known(uint8_t m)
{
    return m <= BLE_MANEUVER_ARRIVE;
}

ble_result_t ble_decode_nav(const uint8_t *data, size_t length, uint8_t *out_flags,
                            ble_nav_data_t *out_nav)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_NAVIGATION) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_NAV_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    const uint8_t *body = header.body;
    const int32_t lat = ble_read_i32_le(&body[0]);
    const int32_t lng = ble_read_i32_le(&body[4]);
    const uint16_t speed = ble_read_u16_le(&body[8]);
    const uint16_t heading = ble_read_u16_le(&body[10]);
    const uint16_t distance = ble_read_u16_le(&body[12]);
    const uint8_t maneuver = body[14];
    const uint8_t reserved1 = body[15];
    if (reserved1 != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if (!ble_maneuver_is_known(maneuver)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    /* street_name: 32 bytes, must contain a null terminator */
    const uint8_t *street = &body[16];
    bool terminator_found = false;
    for (size_t i = 0; i < STREET_NAME_FIELD_LEN; ++i) {
        if (street[i] == 0) {
            terminator_found = true;
            break;
        }
    }
    if (!terminator_found) {
        return BLE_ERR_UNTERMINATED_STRING;
    }

    const uint16_t eta = ble_read_u16_le(&body[48]);
    const uint16_t remaining = ble_read_u16_le(&body[50]);
    const uint32_t reserved2 = ble_read_u32_le(&body[52]);
    if (reserved2 != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if (!ble_nav_ranges_ok(lat, lng, speed, heading)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    out_nav->latitude_e7 = lat;
    out_nav->longitude_e7 = lng;
    out_nav->speed_kmh_x10 = speed;
    out_nav->heading_deg_x10 = heading;
    out_nav->distance_to_maneuver_m = distance;
    out_nav->maneuver = (ble_maneuver_t)maneuver;
    memset(out_nav->street_name, 0, sizeof(out_nav->street_name));
    memcpy(out_nav->street_name, street, STREET_NAME_FIELD_LEN);
    out_nav->eta_minutes = eta;
    out_nav->remaining_km_x10 = remaining;
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_nav(const ble_nav_data_t *nav, uint8_t flags, uint8_t *out_buf,
                            size_t out_cap, size_t *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_NAV_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    if (!ble_nav_ranges_ok(nav->latitude_e7, nav->longitude_e7, nav->speed_kmh_x10,
                           nav->heading_deg_x10)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    if (!ble_maneuver_is_known((uint8_t)nav->maneuver)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    /* street_name must fit with a null terminator. */
    size_t name_len = ble_strnlen(nav->street_name, STREET_NAME_FIELD_LEN);
    if (name_len >= STREET_NAME_FIELD_LEN) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    ble_write_header(out_buf, BLE_SCREEN_NAVIGATION, flags, (uint16_t)BLE_PROTOCOL_NAV_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    ble_write_i32_le(&body[0], nav->latitude_e7);
    ble_write_i32_le(&body[4], nav->longitude_e7);
    ble_write_u16_le(&body[8], nav->speed_kmh_x10);
    ble_write_u16_le(&body[10], nav->heading_deg_x10);
    ble_write_u16_le(&body[12], nav->distance_to_maneuver_m);
    body[14] = (uint8_t)nav->maneuver;
    body[15] = 0;
    memset(&body[16], 0, STREET_NAME_FIELD_LEN);
    memcpy(&body[16], nav->street_name, name_len);
    ble_write_u16_le(&body[48], nav->eta_minutes);
    ble_write_u16_le(&body[50], nav->remaining_km_x10);
    ble_write_u32_le(&body[52], 0);
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_NAV_BODY_SIZE;
    }
    return BLE_OK;
}
