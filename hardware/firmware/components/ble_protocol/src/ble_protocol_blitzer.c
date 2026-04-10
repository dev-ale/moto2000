/*
 * ble_protocol_blitzer.c — blitzer (radar/speed-camera) body encoder/decoder.
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <string.h>

static bool ble_camera_type_is_known(uint8_t t)
{
    return t <= BLE_CAMERA_TYPE_UNKNOWN;
}

ble_result_t ble_decode_blitzer(const uint8_t          *data,
                                size_t                  length,
                                uint8_t                *out_flags,
                                ble_blitzer_data_t     *out_blitzer)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_BLITZER) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_BLITZER_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    const uint8_t *body = header.body;

    const uint16_t distance    = ble_read_u16_le(&body[0]);
    const uint16_t speed_limit = ble_read_u16_le(&body[2]);
    const uint16_t current_spd = ble_read_u16_le(&body[4]);
    const uint8_t  cam_type    = body[6];
    const uint8_t  reserved    = body[7];

    if (reserved != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if (!ble_camera_type_is_known(cam_type)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    out_blitzer->distance_meters      = distance;
    out_blitzer->speed_limit_kmh      = speed_limit;
    out_blitzer->current_speed_kmh_x10 = current_spd;
    out_blitzer->camera_type          = (ble_camera_type_t)cam_type;

    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_blitzer(const ble_blitzer_data_t *blitzer,
                                uint8_t                   flags,
                                uint8_t                  *out_buf,
                                size_t                    out_cap,
                                size_t                   *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_BLITZER_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    if (!ble_camera_type_is_known((uint8_t)blitzer->camera_type)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    ble_write_header(out_buf, BLE_SCREEN_BLITZER, flags,
                     (uint16_t)BLE_PROTOCOL_BLITZER_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    ble_write_u16_le(&body[0], blitzer->distance_meters);
    ble_write_u16_le(&body[2], blitzer->speed_limit_kmh);
    ble_write_u16_le(&body[4], blitzer->current_speed_kmh_x10);
    body[6] = (uint8_t)blitzer->camera_type;
    body[7] = 0; /* reserved */

    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_BLITZER_BODY_SIZE;
    }
    return BLE_OK;
}
