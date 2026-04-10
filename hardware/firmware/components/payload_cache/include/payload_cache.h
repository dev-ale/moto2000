/*
 * payload_cache.h — per-screen raw BLE payload cache.
 *
 * Stores the most recently received BLE payload (header + body) for each
 * screen ID so that screen switching can re-render from cached data without
 * waiting for a fresh push from the phone.
 *
 * Pure C, no ESP-IDF dependencies.
 */
#ifndef SCRAMSCREEN_PAYLOAD_CACHE_H
#define SCRAMSCREEN_PAYLOAD_CACHE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Screen IDs range from 0x01 to 0x0D (13 screens). */
#define PAYLOAD_CACHE_MIN_SCREEN_ID ((uint8_t)0x01u)
#define PAYLOAD_CACHE_MAX_SCREEN_ID ((uint8_t)0x0Du)
#define PAYLOAD_CACHE_NUM_SLOTS \
    ((size_t)(PAYLOAD_CACHE_MAX_SCREEN_ID - PAYLOAD_CACHE_MIN_SCREEN_ID + 1u))

/* Largest screen payload is ~128 bytes (altitude), rounded up. */
#define PAYLOAD_CACHE_MAX_PAYLOAD_SIZE ((size_t)256u)

typedef struct {
    uint8_t data[PAYLOAD_CACHE_MAX_PAYLOAD_SIZE];
    size_t len;
    bool valid;
} payload_cache_slot_t;

typedef struct {
    payload_cache_slot_t slots[PAYLOAD_CACHE_NUM_SLOTS];
} payload_cache_t;

/*
 * Initialise (zero) all cache slots.
 */
void payload_cache_init(payload_cache_t *cache);

/*
 * Store a raw BLE payload for the given screen_id.
 * Returns false if screen_id is out of range, data is NULL, or len exceeds
 * PAYLOAD_CACHE_MAX_PAYLOAD_SIZE.
 */
bool payload_cache_store(payload_cache_t *cache, uint8_t screen_id, const uint8_t *data,
                         size_t len);

/*
 * Retrieve the cached payload for screen_id.
 * Copies up to *out_len bytes into out, then sets *out_len to actual size.
 * Returns false if no payload is cached or screen_id is out of range.
 */
bool payload_cache_get(const payload_cache_t *cache, uint8_t screen_id, uint8_t *out,
                       size_t *out_len);

/*
 * Check whether a valid payload exists for this screen.
 */
bool payload_cache_has(const payload_cache_t *cache, uint8_t screen_id);

#ifdef __cplusplus
}
#endif

#endif /* SCRAMSCREEN_PAYLOAD_CACHE_H */
