/*
 * ble_reconnect — ESP32 side of Slice 17 (auto-reconnect + disconnect
 * resilience).
 *
 * Pure C with no ESP-IDF dependencies so the same sources compile under the
 * host-test harness at hardware/firmware/test/host/. Everything in this
 * header is designed to be driven deterministically from Unity tests with a
 * monotonic "now_ms" counter instead of a real system clock.
 *
 * The component exposes two independent pieces:
 *
 *   1. A reconnect state machine (ble_reconnect_fsm_t) that mirrors the
 *      iOS-side FSM in BLECentralClient. It consumes connect/disconnect/
 *      tick events and emits actions (start advertising, wait, none). The
 *      backoff schedule matches the iOS side exactly: 100, 200, 400, 800,
 *      1600, 3000 ms cap. Total worst-case before the fifth attempt is
 *      3100 ms, well under the Slice 17 five-second target.
 *
 *   2. A last-known-payload cache (ble_payload_cache_t) with one slot per
 *      screen id (0x00..0x0D, 14 entries). Lets the ESP32 keep drawing the
 *      most recent frame during an outage and raise a staleness flag once
 *      the entry exceeds a caller-supplied threshold.
 */
#ifndef SCRAMSCREEN_BLE_RECONNECT_H
#define SCRAMSCREEN_BLE_RECONNECT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------ */
/* Reconnect FSM                                                            */
/* ------------------------------------------------------------------------ */

typedef enum {
    BLE_RC_DISCONNECTED = 0,
    BLE_RC_ADVERTISING  = 1,
    BLE_RC_CONNECTED    = 2,
    BLE_RC_BACKOFF      = 3
} ble_reconnect_state_t;

typedef enum {
    BLE_RC_EVENT_CONNECT    = 0,
    BLE_RC_EVENT_DISCONNECT = 1,
    BLE_RC_EVENT_TICK       = 2
} ble_reconnect_event_t;

typedef enum {
    BLE_RC_ACTION_NONE             = 0,
    BLE_RC_ACTION_START_ADVERTISING = 1,
    BLE_RC_ACTION_WAIT             = 2
} ble_reconnect_action_t;

typedef struct {
    ble_reconnect_state_t state;
    uint32_t              backoff_ms;
    uint32_t              next_action_at_ms;
    uint8_t               attempt;
} ble_reconnect_fsm_t;

/* Number of entries in the ms backoff schedule. */
#define BLE_RECONNECT_BACKOFF_STEPS 6

/* Hard cap on the backoff (matches the last entry in the schedule). */
#define BLE_RECONNECT_BACKOFF_CAP_MS 3000u

/*
 * Returns the backoff delay in milliseconds for the given 1-based attempt
 * number, clamped to the final schedule entry. attempt values < 1 are
 * clamped to 1.
 */
uint32_t ble_reconnect_backoff_ms(uint8_t attempt);

/*
 * Resets the FSM to its initial state (BLE_RC_DISCONNECTED, attempt 0).
 */
void ble_reconnect_init(ble_reconnect_fsm_t *fsm);

/*
 * Feeds one event into the FSM and returns the action the caller must
 * perform. now_ms must be monotonically non-decreasing across calls — it
 * is used to stamp BLE_RC_BACKOFF wake times. The FSM itself owns no
 * timers; the caller schedules the next TICK for now_ms >= fsm->next_action_at_ms.
 */
ble_reconnect_action_t ble_reconnect_handle(ble_reconnect_fsm_t *fsm,
                                            ble_reconnect_event_t event,
                                            uint32_t now_ms);

/* ------------------------------------------------------------------------ */
/* Last-known-payload cache                                                 */
/* ------------------------------------------------------------------------ */

/* Max payload body stored per screen. 56B covers the NAV screen; 64 gives
 * a comfortable margin for future screens without inflating the table. */
#define BLE_PAYLOAD_CACHE_BODY_MAX 64

/* Screen IDs range from 0x00..0x0D per docs/ble-protocol.md §Screens. */
#define BLE_PAYLOAD_CACHE_SCREEN_COUNT 14

typedef struct {
    uint8_t  body[BLE_PAYLOAD_CACHE_BODY_MAX];
    uint16_t length;
    uint32_t updated_ms;
    bool     present;
} ble_payload_cache_entry_t;

typedef struct {
    ble_payload_cache_entry_t entries[BLE_PAYLOAD_CACHE_SCREEN_COUNT];
} ble_payload_cache_t;

/* Zeroes every entry in the cache. Safe to call multiple times. */
void ble_payload_cache_init(ble_payload_cache_t *cache);

/*
 * Stores `body` (up to BLE_PAYLOAD_CACHE_BODY_MAX bytes) under `screen_id`
 * stamped with now_ms. Bodies larger than the max are truncated and
 * `length` reflects the stored size. screen_ids outside the valid range are
 * silently dropped.
 */
void ble_payload_cache_store(ble_payload_cache_t *cache,
                             uint8_t screen_id,
                             const uint8_t *body,
                             uint16_t length,
                             uint32_t now_ms);

/*
 * Returns a read-only pointer to the cached entry for `screen_id`, or NULL
 * if the slot has never been written or the id is out of range. The entry
 * is owned by the cache and remains valid until the next store/init for
 * that slot.
 */
const ble_payload_cache_entry_t *ble_payload_cache_get(
    const ble_payload_cache_t *cache, uint8_t screen_id);

/*
 * Returns true iff the entry for `screen_id` is missing OR older than
 * `stale_threshold_ms` relative to `now_ms`. A "never seen" slot counts as
 * stale. Out-of-range ids are reported as stale.
 */
bool ble_payload_cache_is_stale(const ble_payload_cache_t *cache,
                                uint8_t screen_id,
                                uint32_t now_ms,
                                uint32_t stale_threshold_ms);

#ifdef __cplusplus
}
#endif

#endif /* SCRAMSCREEN_BLE_RECONNECT_H */
