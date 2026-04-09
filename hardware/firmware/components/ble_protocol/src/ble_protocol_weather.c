/*
 * ble_protocol_weather.c — weather body encoder/decoder.
 *
 * Wire layout (little-endian, 28 bytes total):
 *   offset 0     : uint8  condition       (BLE_WEATHER_*)
 *   offset 1     : uint8  reserved        (must be 0)
 *   offset 2..3  : int16  temperature_x10 (-500..=600)
 *   offset 4..5  : int16  high_x10        (-500..=600)
 *   offset 6..7  : int16  low_x10         (-500..=600)
 *   offset 8..27 : char[20] location_name (UTF-8, null-terminated)
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <string.h>

#define LOCATION_NAME_FIELD_LEN ((size_t)20)
#define WEATHER_MIN_TEMP_X10    (-500)
#define WEATHER_MAX_TEMP_X10    (600)

static bool ble_weather_temp_in_range(int16_t v)
{
    return v >= WEATHER_MIN_TEMP_X10 && v <= WEATHER_MAX_TEMP_X10;
}

static bool ble_weather_condition_known(uint8_t c)
{
    return c <= BLE_WEATHER_THUNDERSTORM;
}

ble_result_t ble_decode_weather(const uint8_t      *data,
                                size_t              length,
                                uint8_t            *out_flags,
                                ble_weather_data_t *out)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_WEATHER) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_WEATHER_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    const uint8_t *body     = header.body;
    const uint8_t  cond     = body[0];
    const uint8_t  reserved = body[1];
    if (reserved != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if (!ble_weather_condition_known(cond)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    const int16_t temp = ble_read_i16_le(&body[2]);
    const int16_t high = ble_read_i16_le(&body[4]);
    const int16_t low  = ble_read_i16_le(&body[6]);
    if (!ble_weather_temp_in_range(temp) ||
        !ble_weather_temp_in_range(high) ||
        !ble_weather_temp_in_range(low)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    /* location_name: 20 bytes, must contain a null terminator */
    const uint8_t *name             = &body[8];
    bool           terminator_found = false;
    for (size_t i = 0; i < LOCATION_NAME_FIELD_LEN; ++i) {
        if (name[i] == 0) {
            terminator_found = true;
            break;
        }
    }
    if (!terminator_found) {
        return BLE_ERR_UNTERMINATED_STRING;
    }

    out->condition               = (ble_weather_condition_t)cond;
    out->temperature_celsius_x10 = temp;
    out->high_celsius_x10        = high;
    out->low_celsius_x10         = low;
    memset(out->location_name, 0, sizeof(out->location_name));
    memcpy(out->location_name, name, LOCATION_NAME_FIELD_LEN);
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_weather(const ble_weather_data_t *in,
                                uint8_t                   flags,
                                uint8_t                  *out_buf,
                                size_t                    out_cap,
                                size_t                   *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_WEATHER_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    if (!ble_weather_condition_known((uint8_t)in->condition)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    if (!ble_weather_temp_in_range(in->temperature_celsius_x10) ||
        !ble_weather_temp_in_range(in->high_celsius_x10) ||
        !ble_weather_temp_in_range(in->low_celsius_x10)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    const size_t name_len = strnlen(in->location_name, LOCATION_NAME_FIELD_LEN);
    if (name_len >= LOCATION_NAME_FIELD_LEN) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    ble_write_header(out_buf, BLE_SCREEN_WEATHER, flags,
                     (uint16_t)BLE_PROTOCOL_WEATHER_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    body[0] = (uint8_t)in->condition;
    body[1] = 0;
    ble_write_i16_le(&body[2], in->temperature_celsius_x10);
    ble_write_i16_le(&body[4], in->high_celsius_x10);
    ble_write_i16_le(&body[6], in->low_celsius_x10);
    memset(&body[8], 0, LOCATION_NAME_FIELD_LEN);
    memcpy(&body[8], in->location_name, name_len);
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_WEATHER_BODY_SIZE;
    }
    return BLE_OK;
}
