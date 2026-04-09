/*
 * Host-side Unity tests for the ble_reconnect component.
 *
 * These cover every FSM transition plus the last-known-payload cache, and
 * run under the same -Wall -Wextra -Wpedantic -Werror -Wconversion profile
 * as the rest of hardware/firmware/test/host.
 */
#include "ble_reconnect.h"
#include "unity.h"

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

void setUp(void) {}
void tearDown(void) {}

/* ------------------------------------------------------------------------ */
/* Backoff schedule                                                         */
/* ------------------------------------------------------------------------ */

static void test_backoff_schedule_matches_ios(void)
{
    TEST_ASSERT_EQUAL_UINT32(100u, ble_reconnect_backoff_ms(1));
    TEST_ASSERT_EQUAL_UINT32(200u, ble_reconnect_backoff_ms(2));
    TEST_ASSERT_EQUAL_UINT32(400u, ble_reconnect_backoff_ms(3));
    TEST_ASSERT_EQUAL_UINT32(800u, ble_reconnect_backoff_ms(4));
    TEST_ASSERT_EQUAL_UINT32(1600u, ble_reconnect_backoff_ms(5));
    TEST_ASSERT_EQUAL_UINT32(3000u, ble_reconnect_backoff_ms(6));
    /* Cap holds beyond the schedule. */
    TEST_ASSERT_EQUAL_UINT32(3000u, ble_reconnect_backoff_ms(7));
    TEST_ASSERT_EQUAL_UINT32(3000u, ble_reconnect_backoff_ms(200));
}

static void test_backoff_clamps_zero_attempt(void)
{
    TEST_ASSERT_EQUAL_UINT32(100u, ble_reconnect_backoff_ms(0));
}

/* ------------------------------------------------------------------------ */
/* FSM lifecycle                                                            */
/* ------------------------------------------------------------------------ */

static void test_init_zeroes_fsm(void)
{
    ble_reconnect_fsm_t fsm;
    /* Pre-dirty the memory to prove init scrubs everything. */
    memset(&fsm, 0xAB, sizeof(fsm));
    ble_reconnect_init(&fsm);
    TEST_ASSERT_EQUAL_INT(BLE_RC_DISCONNECTED, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(0u, fsm.attempt);
    TEST_ASSERT_EQUAL_UINT32(0u, fsm.backoff_ms);
    TEST_ASSERT_EQUAL_UINT32(0u, fsm.next_action_at_ms);
}

static void test_null_fsm_is_safe(void)
{
    ble_reconnect_init(NULL);
    ble_reconnect_action_t action = ble_reconnect_handle(NULL, BLE_RC_EVENT_CONNECT, 0u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ACTION_NONE, action);
}

static void test_connect_from_disconnected_enters_connected(void)
{
    ble_reconnect_fsm_t fsm;
    ble_reconnect_init(&fsm);
    ble_reconnect_action_t action = ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 0u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ACTION_NONE, action);
    TEST_ASSERT_EQUAL_INT(BLE_RC_CONNECTED, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(0u, fsm.attempt);
}

static void test_duplicate_connect_is_idempotent(void)
{
    ble_reconnect_fsm_t fsm;
    ble_reconnect_init(&fsm);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 0u);
    ble_reconnect_action_t action = ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 50u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ACTION_NONE, action);
    TEST_ASSERT_EQUAL_INT(BLE_RC_CONNECTED, fsm.state);
}

static void test_disconnect_while_disconnected_noop(void)
{
    ble_reconnect_fsm_t fsm;
    ble_reconnect_init(&fsm);
    ble_reconnect_action_t action = ble_reconnect_handle(&fsm, BLE_RC_EVENT_DISCONNECT, 10u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ACTION_NONE, action);
    TEST_ASSERT_EQUAL_INT(BLE_RC_DISCONNECTED, fsm.state);
}

static void test_disconnect_from_connected_enters_backoff(void)
{
    ble_reconnect_fsm_t fsm;
    ble_reconnect_init(&fsm);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 0u);
    ble_reconnect_action_t action = ble_reconnect_handle(&fsm, BLE_RC_EVENT_DISCONNECT, 1000u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ACTION_WAIT, action);
    TEST_ASSERT_EQUAL_INT(BLE_RC_BACKOFF, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(1u, fsm.attempt);
    TEST_ASSERT_EQUAL_UINT32(100u, fsm.backoff_ms);
    TEST_ASSERT_EQUAL_UINT32(1100u, fsm.next_action_at_ms);
}

static void test_tick_before_wake_keeps_waiting(void)
{
    ble_reconnect_fsm_t fsm;
    ble_reconnect_init(&fsm);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 0u);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_DISCONNECT, 1000u);
    ble_reconnect_action_t action = ble_reconnect_handle(&fsm, BLE_RC_EVENT_TICK, 1050u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ACTION_WAIT, action);
    TEST_ASSERT_EQUAL_INT(BLE_RC_BACKOFF, fsm.state);
}

static void test_tick_at_wake_starts_advertising(void)
{
    ble_reconnect_fsm_t fsm;
    ble_reconnect_init(&fsm);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 0u);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_DISCONNECT, 1000u);
    ble_reconnect_action_t action = ble_reconnect_handle(&fsm, BLE_RC_EVENT_TICK, 1100u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ACTION_START_ADVERTISING, action);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ADVERTISING, fsm.state);
}

static void test_tick_outside_backoff_is_noop(void)
{
    ble_reconnect_fsm_t fsm;
    ble_reconnect_init(&fsm);
    ble_reconnect_action_t a1 = ble_reconnect_handle(&fsm, BLE_RC_EVENT_TICK, 50u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ACTION_NONE, a1);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 0u);
    ble_reconnect_action_t a2 = ble_reconnect_handle(&fsm, BLE_RC_EVENT_TICK, 60u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ACTION_NONE, a2);
}

static void test_disconnect_while_advertising_reschedules(void)
{
    ble_reconnect_fsm_t fsm;
    ble_reconnect_init(&fsm);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 0u);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_DISCONNECT, 1000u);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_TICK, 1100u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ADVERTISING, fsm.state);
    /* Advertising failed — disconnect bumps attempt to 2 and schedules
     * the 200 ms slot. */
    ble_reconnect_action_t action = ble_reconnect_handle(&fsm, BLE_RC_EVENT_DISCONNECT, 1200u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ACTION_WAIT, action);
    TEST_ASSERT_EQUAL_INT(BLE_RC_BACKOFF, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(2u, fsm.attempt);
    TEST_ASSERT_EQUAL_UINT32(200u, fsm.backoff_ms);
    TEST_ASSERT_EQUAL_UINT32(1400u, fsm.next_action_at_ms);
}

static void test_backoff_progression_caps_at_3000(void)
{
    ble_reconnect_fsm_t fsm;
    ble_reconnect_init(&fsm);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 0u);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_DISCONNECT, 0u);

    const uint32_t expected[] = { 200u, 400u, 800u, 1600u, 3000u, 3000u, 3000u };
    uint32_t now = 0u;
    for (size_t i = 0; i < sizeof(expected) / sizeof(expected[0]); ++i) {
        /* Wait out the current backoff, transition to ADVERTISING. */
        now += fsm.backoff_ms;
        (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_TICK, now);
        TEST_ASSERT_EQUAL_INT(BLE_RC_ADVERTISING, fsm.state);
        /* Fail the attempt. */
        (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_DISCONNECT, now);
        TEST_ASSERT_EQUAL_UINT32(expected[i], fsm.backoff_ms);
    }
}

static void test_connect_during_backoff_resets_counters(void)
{
    ble_reconnect_fsm_t fsm;
    ble_reconnect_init(&fsm);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 0u);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_DISCONNECT, 500u);
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 600u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_CONNECTED, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(0u, fsm.attempt);
    TEST_ASSERT_EQUAL_UINT32(0u, fsm.backoff_ms);
}

static void test_full_disconnect_reconnect_cycle(void)
{
    ble_reconnect_fsm_t fsm;
    ble_reconnect_init(&fsm);
    /* Start connected. */
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 0u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_CONNECTED, fsm.state);
    /* Drop the link. */
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_DISCONNECT, 100u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_BACKOFF, fsm.state);
    /* Wait out backoff. */
    ble_reconnect_action_t tick = ble_reconnect_handle(&fsm, BLE_RC_EVENT_TICK, 200u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ACTION_START_ADVERTISING, tick);
    TEST_ASSERT_EQUAL_INT(BLE_RC_ADVERTISING, fsm.state);
    /* Peer connects. */
    (void)ble_reconnect_handle(&fsm, BLE_RC_EVENT_CONNECT, 210u);
    TEST_ASSERT_EQUAL_INT(BLE_RC_CONNECTED, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(0u, fsm.attempt);
    /* Total elapsed since disconnect: 110 ms — well under 5 s. */
}

/* ------------------------------------------------------------------------ */
/* Payload cache                                                            */
/* ------------------------------------------------------------------------ */

static void test_cache_init_marks_all_empty(void)
{
    ble_payload_cache_t cache;
    memset(&cache, 0xFF, sizeof(cache));
    ble_payload_cache_init(&cache);
    for (uint8_t id = 0u; id < BLE_PAYLOAD_CACHE_SCREEN_COUNT; ++id) {
        TEST_ASSERT_NULL(ble_payload_cache_get(&cache, id));
        TEST_ASSERT_TRUE(ble_payload_cache_is_stale(&cache, id, 1000u, 500u));
    }
}

static void test_cache_store_and_get(void)
{
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);

    const uint8_t body[] = { 0x10, 0x20, 0x30, 0x40 };
    ble_payload_cache_store(&cache, 0x02, body, (uint16_t)sizeof(body), 1234u);

    const ble_payload_cache_entry_t *entry = ble_payload_cache_get(&cache, 0x02);
    TEST_ASSERT_NOT_NULL(entry);
    TEST_ASSERT_EQUAL_UINT16(4u, entry->length);
    TEST_ASSERT_EQUAL_UINT32(1234u, entry->updated_ms);
    TEST_ASSERT_TRUE(entry->present);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(body, entry->body, sizeof(body));

    /* Other slots remain empty. */
    TEST_ASSERT_NULL(ble_payload_cache_get(&cache, 0x03));
}

static void test_cache_store_truncates_oversize_body(void)
{
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);

    uint8_t big[BLE_PAYLOAD_CACHE_BODY_MAX + 10];
    for (size_t i = 0; i < sizeof(big); ++i) {
        big[i] = (uint8_t)(i & 0xFFu);
    }
    ble_payload_cache_store(&cache, 0x05, big, (uint16_t)sizeof(big), 42u);
    const ble_payload_cache_entry_t *entry = ble_payload_cache_get(&cache, 0x05);
    TEST_ASSERT_NOT_NULL(entry);
    TEST_ASSERT_EQUAL_UINT16((uint16_t)BLE_PAYLOAD_CACHE_BODY_MAX, entry->length);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(big, entry->body, BLE_PAYLOAD_CACHE_BODY_MAX);
}

static void test_cache_store_overwrite_updates_timestamp(void)
{
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);

    const uint8_t v1[] = { 0x01 };
    const uint8_t v2[] = { 0x02, 0x03 };
    ble_payload_cache_store(&cache, 0x00, v1, 1u, 100u);
    ble_payload_cache_store(&cache, 0x00, v2, 2u, 200u);
    const ble_payload_cache_entry_t *entry = ble_payload_cache_get(&cache, 0x00);
    TEST_ASSERT_NOT_NULL(entry);
    TEST_ASSERT_EQUAL_UINT16(2u, entry->length);
    TEST_ASSERT_EQUAL_UINT32(200u, entry->updated_ms);
    TEST_ASSERT_EQUAL_UINT8(0x02u, entry->body[0]);
    TEST_ASSERT_EQUAL_UINT8(0x03u, entry->body[1]);
    /* Tail should be zeroed beyond the stored length. */
    TEST_ASSERT_EQUAL_UINT8(0x00u, entry->body[2]);
}

static void test_cache_store_invalid_screen_id_ignored(void)
{
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);
    const uint8_t body[] = { 0xAA };
    ble_payload_cache_store(&cache, 0xFF, body, 1u, 1u);
    ble_payload_cache_store(&cache, BLE_PAYLOAD_CACHE_SCREEN_COUNT, body, 1u, 1u);
    /* Nothing leaks into valid slots. */
    for (uint8_t id = 0u; id < BLE_PAYLOAD_CACHE_SCREEN_COUNT; ++id) {
        TEST_ASSERT_NULL(ble_payload_cache_get(&cache, id));
    }
}

static void test_cache_get_rejects_invalid_screen_id(void)
{
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);
    TEST_ASSERT_NULL(ble_payload_cache_get(&cache, 0xFF));
    TEST_ASSERT_NULL(ble_payload_cache_get(NULL, 0x00));
}

static void test_cache_staleness_threshold(void)
{
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);
    const uint8_t body[] = { 0x00 };
    ble_payload_cache_store(&cache, 0x01, body, 1u, 1000u);

    TEST_ASSERT_FALSE(ble_payload_cache_is_stale(&cache, 0x01, 1500u, 2000u));
    /* Exactly at threshold is NOT stale. */
    TEST_ASSERT_FALSE(ble_payload_cache_is_stale(&cache, 0x01, 3000u, 2000u));
    /* Past threshold. */
    TEST_ASSERT_TRUE(ble_payload_cache_is_stale(&cache, 0x01, 3001u, 2000u));
}

static void test_cache_staleness_guards_against_past(void)
{
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);
    const uint8_t body[] = { 0x00 };
    ble_payload_cache_store(&cache, 0x01, body, 1u, 5000u);
    /* If caller hands us a lower now_ms than the entry (monotonic clock
     * fail), treat as fresh rather than produce a huge wrap-around. */
    TEST_ASSERT_FALSE(ble_payload_cache_is_stale(&cache, 0x01, 4000u, 1000u));
}

static void test_cache_staleness_null_and_out_of_range(void)
{
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);
    TEST_ASSERT_TRUE(ble_payload_cache_is_stale(NULL, 0x00, 0u, 1000u));
    TEST_ASSERT_TRUE(ble_payload_cache_is_stale(&cache, 0xFFu, 0u, 1000u));
}

static void test_cache_store_null_body_with_zero_length(void)
{
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);
    ble_payload_cache_store(&cache, 0x03, NULL, 0u, 42u);
    const ble_payload_cache_entry_t *entry = ble_payload_cache_get(&cache, 0x03);
    TEST_ASSERT_NOT_NULL(entry);
    TEST_ASSERT_EQUAL_UINT16(0u, entry->length);
    TEST_ASSERT_EQUAL_UINT32(42u, entry->updated_ms);
}

static void test_cache_null_init_is_safe(void)
{
    ble_payload_cache_init(NULL);
    ble_payload_cache_store(NULL, 0, NULL, 0, 0);
    /* If we got here without crashing, the NULL checks work. */
    TEST_PASS();
}

/* ------------------------------------------------------------------------ */
/* Runner                                                                   */
/* ------------------------------------------------------------------------ */

int main(void)
{
    UNITY_BEGIN();

    RUN_TEST(test_backoff_schedule_matches_ios);
    RUN_TEST(test_backoff_clamps_zero_attempt);

    RUN_TEST(test_init_zeroes_fsm);
    RUN_TEST(test_null_fsm_is_safe);
    RUN_TEST(test_connect_from_disconnected_enters_connected);
    RUN_TEST(test_duplicate_connect_is_idempotent);
    RUN_TEST(test_disconnect_while_disconnected_noop);
    RUN_TEST(test_disconnect_from_connected_enters_backoff);
    RUN_TEST(test_tick_before_wake_keeps_waiting);
    RUN_TEST(test_tick_at_wake_starts_advertising);
    RUN_TEST(test_tick_outside_backoff_is_noop);
    RUN_TEST(test_disconnect_while_advertising_reschedules);
    RUN_TEST(test_backoff_progression_caps_at_3000);
    RUN_TEST(test_connect_during_backoff_resets_counters);
    RUN_TEST(test_full_disconnect_reconnect_cycle);

    RUN_TEST(test_cache_init_marks_all_empty);
    RUN_TEST(test_cache_store_and_get);
    RUN_TEST(test_cache_store_truncates_oversize_body);
    RUN_TEST(test_cache_store_overwrite_updates_timestamp);
    RUN_TEST(test_cache_store_invalid_screen_id_ignored);
    RUN_TEST(test_cache_get_rejects_invalid_screen_id);
    RUN_TEST(test_cache_staleness_threshold);
    RUN_TEST(test_cache_staleness_guards_against_past);
    RUN_TEST(test_cache_staleness_null_and_out_of_range);
    RUN_TEST(test_cache_store_null_body_with_zero_length);
    RUN_TEST(test_cache_null_init_is_safe);

    return UNITY_END();
}
