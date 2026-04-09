/*
 * ble_reconnect — implementation.
 *
 * See include/ble_reconnect.h for the API contract. Pure C, no ESP-IDF
 * includes, so the same translation unit compiles under the host-test
 * harness.
 */
#include "ble_reconnect.h"

#include <string.h>

/* Backoff schedule in milliseconds, indexed by (attempt - 1). Matches the
 * iOS-side ReconnectStateMachine.backoffSchedule exactly. */
static const uint32_t k_backoff_schedule_ms[BLE_RECONNECT_BACKOFF_STEPS] = {
    100u, 200u, 400u, 800u, 1600u, 3000u
};

uint32_t ble_reconnect_backoff_ms(uint8_t attempt)
{
    uint8_t clamped = (attempt == 0u) ? 1u : attempt;
    size_t index = (size_t)(clamped - 1u);
    if (index >= BLE_RECONNECT_BACKOFF_STEPS) {
        index = BLE_RECONNECT_BACKOFF_STEPS - 1u;
    }
    return k_backoff_schedule_ms[index];
}

void ble_reconnect_init(ble_reconnect_fsm_t *fsm)
{
    if (fsm == NULL) {
        return;
    }
    fsm->state = BLE_RC_DISCONNECTED;
    fsm->backoff_ms = 0u;
    fsm->next_action_at_ms = 0u;
    fsm->attempt = 0u;
}

/* Helper: schedule the next backoff slot using the FSM's current attempt
 * count. Caller must have already bumped `attempt`. */
static ble_reconnect_action_t schedule_backoff(ble_reconnect_fsm_t *fsm,
                                               uint32_t now_ms)
{
    uint32_t delay = ble_reconnect_backoff_ms(fsm->attempt);
    fsm->backoff_ms = delay;
    fsm->next_action_at_ms = now_ms + delay;
    fsm->state = BLE_RC_BACKOFF;
    return BLE_RC_ACTION_WAIT;
}

ble_reconnect_action_t ble_reconnect_handle(ble_reconnect_fsm_t *fsm,
                                            ble_reconnect_event_t event,
                                            uint32_t now_ms)
{
    if (fsm == NULL) {
        return BLE_RC_ACTION_NONE;
    }

    switch (event) {
    case BLE_RC_EVENT_CONNECT:
        if (fsm->state == BLE_RC_CONNECTED) {
            return BLE_RC_ACTION_NONE;
        }
        fsm->state = BLE_RC_CONNECTED;
        fsm->attempt = 0u;
        fsm->backoff_ms = 0u;
        fsm->next_action_at_ms = 0u;
        return BLE_RC_ACTION_NONE;

    case BLE_RC_EVENT_DISCONNECT:
        if (fsm->state == BLE_RC_DISCONNECTED) {
            return BLE_RC_ACTION_NONE;
        }
        if (fsm->state == BLE_RC_CONNECTED) {
            fsm->attempt = 1u;
        } else {
            /* ADVERTISING or BACKOFF: another attempt failed. */
            if (fsm->attempt < 0xFFu) {
                fsm->attempt = (uint8_t)(fsm->attempt + 1u);
            }
            if (fsm->attempt == 0u) {
                fsm->attempt = 1u;
            }
        }
        return schedule_backoff(fsm, now_ms);

    case BLE_RC_EVENT_TICK:
        if (fsm->state != BLE_RC_BACKOFF) {
            return BLE_RC_ACTION_NONE;
        }
        if (now_ms < fsm->next_action_at_ms) {
            return BLE_RC_ACTION_WAIT;
        }
        fsm->state = BLE_RC_ADVERTISING;
        return BLE_RC_ACTION_START_ADVERTISING;

    default:
        return BLE_RC_ACTION_NONE;
    }
}

/* ------------------------------------------------------------------------ */
/* Payload cache                                                            */
/* ------------------------------------------------------------------------ */

void ble_payload_cache_init(ble_payload_cache_t *cache)
{
    if (cache == NULL) {
        return;
    }
    memset(cache, 0, sizeof(*cache));
}

void ble_payload_cache_store(ble_payload_cache_t *cache,
                             uint8_t screen_id,
                             const uint8_t *body,
                             uint16_t length,
                             uint32_t now_ms)
{
    if (cache == NULL) {
        return;
    }
    if (screen_id >= BLE_PAYLOAD_CACHE_SCREEN_COUNT) {
        return;
    }
    ble_payload_cache_entry_t *entry = &cache->entries[screen_id];

    uint16_t to_copy = length;
    if (to_copy > (uint16_t)BLE_PAYLOAD_CACHE_BODY_MAX) {
        to_copy = (uint16_t)BLE_PAYLOAD_CACHE_BODY_MAX;
    }
    if (body != NULL && to_copy > 0u) {
        memcpy(entry->body, body, (size_t)to_copy);
    }
    /* Zero any unused tail so old data doesn't leak through get(). */
    if (to_copy < (uint16_t)BLE_PAYLOAD_CACHE_BODY_MAX) {
        memset(&entry->body[to_copy], 0,
               (size_t)((uint16_t)BLE_PAYLOAD_CACHE_BODY_MAX - to_copy));
    }
    entry->length = to_copy;
    entry->updated_ms = now_ms;
    entry->present = true;
}

const ble_payload_cache_entry_t *ble_payload_cache_get(
    const ble_payload_cache_t *cache, uint8_t screen_id)
{
    if (cache == NULL) {
        return NULL;
    }
    if (screen_id >= BLE_PAYLOAD_CACHE_SCREEN_COUNT) {
        return NULL;
    }
    const ble_payload_cache_entry_t *entry = &cache->entries[screen_id];
    if (!entry->present) {
        return NULL;
    }
    return entry;
}

bool ble_payload_cache_is_stale(const ble_payload_cache_t *cache,
                                uint8_t screen_id,
                                uint32_t now_ms,
                                uint32_t stale_threshold_ms)
{
    if (cache == NULL) {
        return true;
    }
    if (screen_id >= BLE_PAYLOAD_CACHE_SCREEN_COUNT) {
        return true;
    }
    const ble_payload_cache_entry_t *entry = &cache->entries[screen_id];
    if (!entry->present) {
        return true;
    }
    /* now_ms is monotonic; protect against callers that hand us the past. */
    if (now_ms < entry->updated_ms) {
        return false;
    }
    uint32_t elapsed = now_ms - entry->updated_ms;
    return elapsed > stale_threshold_ms;
}
