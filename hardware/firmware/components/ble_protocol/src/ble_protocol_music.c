/*
 * ble_protocol_music.c — music body encoder/decoder.
 *
 * Wire format (86 bytes) defined in docs/ble-protocol.md:
 *
 *   offset 0  : uint8  music_flags (bit 0 = playing, bits 1..7 reserved)
 *   offset 1  : uint8  reserved (must be 0)
 *   offset 2  : uint16 position_seconds (0xFFFF = unknown)
 *   offset 4  : uint16 duration_seconds (0xFFFF = unknown)
 *   offset 6  : char[32] title  (UTF-8, null-terminated, <=31 bytes)
 *   offset 38 : char[24] artist (UTF-8, null-terminated, <=23 bytes)
 *   offset 62 : char[24] album  (UTF-8, null-terminated, <=23 bytes)
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <string.h>

#define MUSIC_TITLE_LEN  ((size_t)32)
#define MUSIC_ARTIST_LEN ((size_t)24)
#define MUSIC_ALBUM_LEN  ((size_t)24)

#define MUSIC_TITLE_OFFSET  ((size_t)6)
#define MUSIC_ARTIST_OFFSET ((size_t)38)
#define MUSIC_ALBUM_OFFSET  ((size_t)62)

static bool field_is_terminated(const uint8_t *field, size_t len)
{
    for (size_t i = 0; i < len; ++i) {
        if (field[i] == 0) {
            return true;
        }
    }
    return false;
}

ble_result_t ble_decode_music(const uint8_t    *data,
                              size_t            length,
                              uint8_t          *out_flags,
                              ble_music_data_t *out)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_MUSIC) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_MUSIC_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }

    const uint8_t *body     = header.body;
    const uint8_t  flags    = body[0];
    const uint8_t  reserved = body[1];
    if (reserved != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if ((flags & BLE_MUSIC_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    const uint16_t position = ble_read_u16_le(&body[2]);
    const uint16_t duration = ble_read_u16_le(&body[4]);

    if (!field_is_terminated(&body[MUSIC_TITLE_OFFSET], MUSIC_TITLE_LEN)) {
        return BLE_ERR_UNTERMINATED_STRING;
    }
    if (!field_is_terminated(&body[MUSIC_ARTIST_OFFSET], MUSIC_ARTIST_LEN)) {
        return BLE_ERR_UNTERMINATED_STRING;
    }
    if (!field_is_terminated(&body[MUSIC_ALBUM_OFFSET], MUSIC_ALBUM_LEN)) {
        return BLE_ERR_UNTERMINATED_STRING;
    }

    out->music_flags      = flags;
    out->position_seconds = position;
    out->duration_seconds = duration;
    memset(out->title, 0, sizeof(out->title));
    memcpy(out->title, &body[MUSIC_TITLE_OFFSET], MUSIC_TITLE_LEN);
    memset(out->artist, 0, sizeof(out->artist));
    memcpy(out->artist, &body[MUSIC_ARTIST_OFFSET], MUSIC_ARTIST_LEN);
    memset(out->album, 0, sizeof(out->album));
    memcpy(out->album, &body[MUSIC_ALBUM_OFFSET], MUSIC_ALBUM_LEN);
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_music(const ble_music_data_t *in,
                              uint8_t                 flags,
                              uint8_t                *out_buf,
                              size_t                  out_cap,
                              size_t                 *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_MUSIC_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    if ((in->music_flags & BLE_MUSIC_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    const size_t title_len  = strnlen(in->title,  MUSIC_TITLE_LEN);
    const size_t artist_len = strnlen(in->artist, MUSIC_ARTIST_LEN);
    const size_t album_len  = strnlen(in->album,  MUSIC_ALBUM_LEN);
    if (title_len  >= MUSIC_TITLE_LEN  ||
        artist_len >= MUSIC_ARTIST_LEN ||
        album_len  >= MUSIC_ALBUM_LEN) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    ble_write_header(out_buf, BLE_SCREEN_MUSIC, flags, (uint16_t)BLE_PROTOCOL_MUSIC_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    body[0] = in->music_flags;
    body[1] = 0;
    ble_write_u16_le(&body[2], in->position_seconds);
    ble_write_u16_le(&body[4], in->duration_seconds);
    memset(&body[MUSIC_TITLE_OFFSET],  0, MUSIC_TITLE_LEN);
    memcpy(&body[MUSIC_TITLE_OFFSET],  in->title,  title_len);
    memset(&body[MUSIC_ARTIST_OFFSET], 0, MUSIC_ARTIST_LEN);
    memcpy(&body[MUSIC_ARTIST_OFFSET], in->artist, artist_len);
    memset(&body[MUSIC_ALBUM_OFFSET],  0, MUSIC_ALBUM_LEN);
    memcpy(&body[MUSIC_ALBUM_OFFSET],  in->album,  album_len);
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_MUSIC_BODY_SIZE;
    }
    return BLE_OK;
}
