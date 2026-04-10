/*
 * payload_cache.c — implementation. See include/payload_cache.h for the API.
 */
#include "payload_cache.h"

#include <string.h>

static bool valid_screen_id(uint8_t screen_id)
{
    return screen_id >= PAYLOAD_CACHE_MIN_SCREEN_ID && screen_id <= PAYLOAD_CACHE_MAX_SCREEN_ID;
}

static size_t slot_index(uint8_t screen_id)
{
    return (size_t)(screen_id - PAYLOAD_CACHE_MIN_SCREEN_ID);
}

void payload_cache_init(payload_cache_t *cache)
{
    if (cache == NULL) {
        return;
    }
    memset(cache, 0, sizeof(*cache));
}

bool payload_cache_store(payload_cache_t *cache, uint8_t screen_id, const uint8_t *data, size_t len)
{
    if (cache == NULL || data == NULL) {
        return false;
    }
    if (!valid_screen_id(screen_id)) {
        return false;
    }
    if (len == 0 || len > PAYLOAD_CACHE_MAX_PAYLOAD_SIZE) {
        return false;
    }

    payload_cache_slot_t *slot = &cache->slots[slot_index(screen_id)];
    memcpy(slot->data, data, len);
    slot->len = len;
    slot->valid = true;
    return true;
}

bool payload_cache_get(const payload_cache_t *cache, uint8_t screen_id, uint8_t *out,
                       size_t *out_len)
{
    if (cache == NULL || out == NULL || out_len == NULL) {
        return false;
    }
    if (!valid_screen_id(screen_id)) {
        return false;
    }

    const payload_cache_slot_t *slot = &cache->slots[slot_index(screen_id)];
    if (!slot->valid) {
        return false;
    }

    size_t copy_len = slot->len;
    if (copy_len > *out_len) {
        copy_len = *out_len;
    }
    memcpy(out, slot->data, copy_len);
    *out_len = slot->len;
    return true;
}

bool payload_cache_has(const payload_cache_t *cache, uint8_t screen_id)
{
    if (cache == NULL) {
        return false;
    }
    if (!valid_screen_id(screen_id)) {
        return false;
    }
    return cache->slots[slot_index(screen_id)].valid;
}
