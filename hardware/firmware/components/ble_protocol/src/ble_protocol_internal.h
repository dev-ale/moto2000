/*
 * Internal helpers shared between the header and per-screen codec files.
 */
#ifndef BLE_PROTOCOL_INTERNAL_H
#define BLE_PROTOCOL_INTERNAL_H

#include <stdint.h>
#include <string.h>

#include "ble_protocol.h"

static inline uint16_t ble_read_u16_le(const uint8_t *p)
{
    return (uint16_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8));
}

static inline uint32_t ble_read_u32_le(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static inline int32_t ble_read_i32_le(const uint8_t *p)
{
    return (int32_t)ble_read_u32_le(p);
}

static inline uint64_t ble_read_u64_le(const uint8_t *p)
{
    uint64_t value = 0;
    for (int i = 0; i < 8; ++i) {
        value |= (uint64_t)p[i] << (8 * i);
    }
    return value;
}

static inline int64_t ble_read_i64_le(const uint8_t *p)
{
    return (int64_t)ble_read_u64_le(p);
}

static inline void ble_write_u16_le(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
}

static inline void ble_write_i16_le(uint8_t *p, int16_t v)
{
    ble_write_u16_le(p, (uint16_t)v);
}

static inline void ble_write_u32_le(uint8_t *p, uint32_t v)
{
    for (int i = 0; i < 4; ++i) {
        p[i] = (uint8_t)((v >> (8 * i)) & 0xFFU);
    }
}

static inline void ble_write_i32_le(uint8_t *p, int32_t v)
{
    ble_write_u32_le(p, (uint32_t)v);
}

static inline void ble_write_u64_le(uint8_t *p, uint64_t v)
{
    for (int i = 0; i < 8; ++i) {
        p[i] = (uint8_t)((v >> (8 * i)) & 0xFFU);
    }
}

static inline void ble_write_i64_le(uint8_t *p, int64_t v)
{
    ble_write_u64_le(p, (uint64_t)v);
}

/* True if screen_id is a recognised enum value. */
bool ble_is_known_screen(uint8_t screen_id);

/* Expected body size for a known screen, or 0 if variable/not defined yet. */
size_t ble_expected_body_size(ble_screen_id_t screen);

/*
 * Writes the 8-byte header into `out`. Caller is responsible for ensuring
 * `out` has at least BLE_PROTOCOL_HEADER_SIZE bytes.
 */
void ble_write_header(uint8_t        *out,
                      ble_screen_id_t screen,
                      uint8_t         flags,
                      uint16_t        body_length);

#endif /* BLE_PROTOCOL_INTERNAL_H */
