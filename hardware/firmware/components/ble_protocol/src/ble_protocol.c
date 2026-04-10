/*
 * ble_protocol.c — header parsing and shared helpers.
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <stddef.h>
#include <string.h>

const char *ble_result_name(ble_result_t result)
{
    switch (result) {
    case BLE_OK:
        return "ok";
    case BLE_ERR_TRUNCATED_HEADER:
        return "truncatedHeader";
    case BLE_ERR_UNSUPPORTED_VERSION:
        return "unsupportedVersion";
    case BLE_ERR_INVALID_RESERVED:
        return "invalidReserved";
    case BLE_ERR_UNKNOWN_SCREEN_ID:
        return "unknownScreenId";
    case BLE_ERR_TRUNCATED_BODY:
        return "truncatedBody";
    case BLE_ERR_BODY_LENGTH_MISMATCH:
        return "bodyLengthMismatch";
    case BLE_ERR_RESERVED_FLAGS_SET:
        return "reservedFlagsSet";
    case BLE_ERR_UNTERMINATED_STRING:
        return "unterminatedString";
    case BLE_ERR_VALUE_OUT_OF_RANGE:
        return "valueOutOfRange";
    case BLE_ERR_NON_ZERO_BODY_RESERVED:
        return "nonZeroBodyReserved";
    case BLE_ERR_BUFFER_TOO_SMALL:
        return "bufferTooSmall";
    case BLE_ERR_UNKNOWN_COMMAND:
        return "unknownCommand";
    case BLE_ERR_INVALID_COMMAND_VALUE:
        return "invalidCommandValue";
    default:
        return "unknown";
    }
}

bool ble_is_known_screen(uint8_t screen_id)
{
    switch (screen_id) {
    case BLE_SCREEN_NAVIGATION:
    case BLE_SCREEN_SPEED_HEADING:
    case BLE_SCREEN_COMPASS:
    case BLE_SCREEN_WEATHER:
    case BLE_SCREEN_TRIP_STATS:
    case BLE_SCREEN_MUSIC:
    case BLE_SCREEN_LEAN_ANGLE:
    case BLE_SCREEN_BLITZER:
    case BLE_SCREEN_INCOMING_CALL:
    case BLE_SCREEN_FUEL_ESTIMATE:
    case BLE_SCREEN_ALTITUDE:
    case BLE_SCREEN_APPOINTMENT:
    case BLE_SCREEN_CLOCK:
        return true;
    default:
        return false;
    }
}

size_t ble_expected_body_size(ble_screen_id_t screen)
{
    switch (screen) {
    case BLE_SCREEN_CLOCK:
        return BLE_PROTOCOL_CLOCK_BODY_SIZE;
    case BLE_SCREEN_NAVIGATION:
        return BLE_PROTOCOL_NAV_BODY_SIZE;
    case BLE_SCREEN_SPEED_HEADING:
        return BLE_PROTOCOL_SPEED_HEADING_BODY_SIZE;
    case BLE_SCREEN_COMPASS:
        return BLE_PROTOCOL_COMPASS_BODY_SIZE;
    case BLE_SCREEN_TRIP_STATS:
        return BLE_PROTOCOL_TRIP_STATS_BODY_SIZE;
    case BLE_SCREEN_WEATHER:
        return BLE_PROTOCOL_WEATHER_BODY_SIZE;
    case BLE_SCREEN_LEAN_ANGLE:
        return BLE_PROTOCOL_LEAN_ANGLE_BODY_SIZE;
    case BLE_SCREEN_MUSIC:
        return BLE_PROTOCOL_MUSIC_BODY_SIZE;
    case BLE_SCREEN_APPOINTMENT:
        return BLE_PROTOCOL_APPOINTMENT_BODY_SIZE;
    case BLE_SCREEN_FUEL_ESTIMATE:
        return BLE_PROTOCOL_FUEL_BODY_SIZE;
    case BLE_SCREEN_ALTITUDE:
        return BLE_PROTOCOL_ALTITUDE_BODY_SIZE;
    case BLE_SCREEN_INCOMING_CALL:
        return BLE_PROTOCOL_INCOMING_CALL_BODY_SIZE;
    case BLE_SCREEN_BLITZER:
        return BLE_PROTOCOL_BLITZER_BODY_SIZE;
    default:
        return 0;
    }
}

void ble_write_header(uint8_t *out, ble_screen_id_t screen, uint8_t flags, uint16_t body_length)
{
    out[0] = BLE_PROTOCOL_VERSION;
    out[1] = (uint8_t)screen;
    out[2] = flags;
    out[3] = 0; /* reserved */
    ble_write_u16_le(&out[4], body_length);
    ble_write_u16_le(&out[6], 0); /* trailing reserved */
}

ble_result_t ble_decode_header(const uint8_t *data, size_t length, ble_header_t *out_header)
{
    if (length < BLE_PROTOCOL_HEADER_SIZE) {
        return BLE_ERR_TRUNCATED_HEADER;
    }
    if (data[0] != BLE_PROTOCOL_VERSION) {
        return BLE_ERR_UNSUPPORTED_VERSION;
    }
    const uint8_t flags = data[2];
    const uint8_t reserved = data[3];
    const uint16_t declared = ble_read_u16_le(&data[4]);
    const uint16_t trailing = ble_read_u16_le(&data[6]);
    if (reserved != 0 || trailing != 0) {
        return BLE_ERR_INVALID_RESERVED;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    if (!ble_is_known_screen(data[1])) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    const ble_screen_id_t screen = (ble_screen_id_t)data[1];
    const size_t expected = ble_expected_body_size(screen);
    if (expected != 0 && (size_t)declared != expected) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    if ((size_t)declared > length - BLE_PROTOCOL_HEADER_SIZE) {
        return BLE_ERR_TRUNCATED_BODY;
    }
    out_header->screen_id = screen;
    out_header->flags = flags;
    out_header->body_length = declared;
    out_header->body = data + BLE_PROTOCOL_HEADER_SIZE;
    return BLE_OK;
}
