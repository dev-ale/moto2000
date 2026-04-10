/*
 * test_integration.c — host-side integration test that simulates the full
 * app_main boot-sequence wiring without LVGL or ESP-IDF.
 *
 * Exercises the dispatch path: encoded BLE payload -> ble_server_handlers
 * -> screen_fsm + payload_cache + reconnect_fsm.
 */

#include "unity.h"

#include "ble_protocol.h"
#include "ble_reconnect.h"
#include "ble_server_handlers.h"
#include "screen_fsm.h"

#include <string.h>

/* Mirrors the static state in app_main. */
static screen_fsm_t         s_fsm;
static ble_reconnect_fsm_t  s_reconnect;
static ble_payload_cache_t  s_cache;

void setUp(void)
{
    screen_fsm_init(&s_fsm, BLE_SCREEN_CLOCK);
    ble_reconnect_init(&s_reconnect);
    ble_payload_cache_init(&s_cache);
}

void tearDown(void) {}

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */

static size_t encode_clock(uint8_t *buf, size_t cap, uint8_t flags)
{
    ble_clock_data_t clk = {
        .unix_time         = 1700000000,
        .tz_offset_minutes = 60,
        .is_24h            = true,
    };
    size_t written = 0;
    ble_result_t rc = ble_encode_clock(&clk, flags, buf, cap, &written);
    TEST_ASSERT_EQUAL(BLE_OK, rc);
    return written;
}

static size_t encode_speed(uint8_t *buf, size_t cap, uint8_t flags)
{
    ble_speed_heading_data_t spd = {
        .speed_kmh_x10          = 1234,
        .heading_deg_x10        = 1800,
        .altitude_m             = 450,
        .temperature_celsius_x10 = 225,
    };
    size_t written = 0;
    ble_result_t rc = ble_encode_speed_heading(&spd, flags, buf, cap, &written);
    TEST_ASSERT_EQUAL(BLE_OK, rc);
    return written;
}

static size_t encode_control_set_active(uint8_t *buf, size_t cap,
                                        uint8_t screen_id)
{
    ble_control_payload_t ctrl = {
        .command    = BLE_CONTROL_CMD_SET_ACTIVE_SCREEN,
        .screen_id  = screen_id,
        .brightness = 0,
    };
    size_t written = 0;
    ble_result_t rc = ble_encode_control(&ctrl, buf, cap, &written);
    TEST_ASSERT_EQUAL(BLE_OK, rc);
    return written;
}

/* ------------------------------------------------------------------ */
/* Integration scenario 1: boot -> clock data -> switch to speed       */
/* ------------------------------------------------------------------ */

static void test_boot_clock_then_switch_to_speed(void)
{
    /* After init the FSM is ACTIVE with clock as the active screen. */
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_CLOCK, s_fsm.active_screen_id);

    /* Simulate BLE connection. */
    ble_server_handle_connection_change(true, &s_reconnect, 100);
    TEST_ASSERT_EQUAL(BLE_RC_CONNECTED, s_reconnect.state);

    /* Feed a clock payload. */
    uint8_t buf[128];
    size_t len = encode_clock(buf, sizeof(buf), 0);
    ble_server_handle_screen_data(buf, len, &s_fsm, &s_cache, 200);

    /* FSM stays ACTIVE, clock screen rendered, cache updated. */
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_CLOCK, s_fsm.current_display_id);

    const ble_payload_cache_entry_t *entry =
        ble_payload_cache_get(&s_cache, BLE_SCREEN_CLOCK);
    TEST_ASSERT_NOT_NULL(entry);
    TEST_ASSERT_TRUE(entry->present);
    TEST_ASSERT_EQUAL(200u, entry->updated_ms);

    /* Control: SET_ACTIVE(speed). */
    len = encode_control_set_active(buf, sizeof(buf), BLE_SCREEN_SPEED_HEADING);
    ble_server_handle_control(buf, len, &s_fsm);

    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_SPEED_HEADING, s_fsm.active_screen_id);
    TEST_ASSERT_EQUAL(BLE_SCREEN_SPEED_HEADING, s_fsm.current_display_id);

    /* Feed a speed payload. */
    len = encode_speed(buf, sizeof(buf), 0);
    ble_server_handle_screen_data(buf, len, &s_fsm, &s_cache, 300);

    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_SPEED_HEADING, s_fsm.current_display_id);

    const ble_payload_cache_entry_t *speed_entry =
        ble_payload_cache_get(&s_cache, BLE_SCREEN_SPEED_HEADING);
    TEST_ASSERT_NOT_NULL(speed_entry);
    TEST_ASSERT_TRUE(speed_entry->present);
    TEST_ASSERT_EQUAL(BLE_PROTOCOL_SPEED_HEADING_BODY_SIZE, speed_entry->length);
}

/* ------------------------------------------------------------------ */
/* Integration scenario 2: disconnect -> reconnect cycle               */
/* ------------------------------------------------------------------ */

static void test_disconnect_reconnect_cycle(void)
{
    /* Connect first. */
    ble_server_handle_connection_change(true, &s_reconnect, 100);
    TEST_ASSERT_EQUAL(BLE_RC_CONNECTED, s_reconnect.state);

    /* Feed clock data while connected. */
    uint8_t buf[128];
    size_t len = encode_clock(buf, sizeof(buf), 0);
    ble_server_handle_screen_data(buf, len, &s_fsm, &s_cache, 200);

    /* Disconnect. */
    ble_server_handle_connection_change(false, &s_reconnect, 300);
    TEST_ASSERT_TRUE(s_reconnect.state != BLE_RC_CONNECTED);

    /* Cached clock data should still be present. */
    const ble_payload_cache_entry_t *entry =
        ble_payload_cache_get(&s_cache, BLE_SCREEN_CLOCK);
    TEST_ASSERT_NOT_NULL(entry);
    TEST_ASSERT_TRUE(entry->present);
    TEST_ASSERT_EQUAL(200u, entry->updated_ms);

    /* The cache entry should be considered stale after the threshold. */
    TEST_ASSERT_TRUE(
        ble_payload_cache_is_stale(&s_cache, BLE_SCREEN_CLOCK, 2300, 2000));
    /* But not stale if checked quickly after the update. */
    TEST_ASSERT_FALSE(
        ble_payload_cache_is_stale(&s_cache, BLE_SCREEN_CLOCK, 300, 2000));

    /* Reconnect. */
    ble_server_handle_connection_change(true, &s_reconnect, 500);
    TEST_ASSERT_EQUAL(BLE_RC_CONNECTED, s_reconnect.state);

    /* FSM should still be in ACTIVE — disconnect does not alter it. */
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_CLOCK, s_fsm.active_screen_id);
}

/* ------------------------------------------------------------------ */
/* Integration scenario 3: alert overlay during active screen          */
/* ------------------------------------------------------------------ */

static void test_alert_overlay_and_clear(void)
{
    /* Connect and set speed as active. */
    ble_server_handle_connection_change(true, &s_reconnect, 100);

    uint8_t buf[128];
    size_t len = encode_control_set_active(buf, sizeof(buf),
                                            BLE_SCREEN_SPEED_HEADING);
    ble_server_handle_control(buf, len, &s_fsm);
    TEST_ASSERT_EQUAL(BLE_SCREEN_SPEED_HEADING, s_fsm.active_screen_id);

    /* Incoming call with ALERT flag. */
    ble_incoming_call_data_t call = {
        .call_state    = BLE_CALL_INCOMING,
        .caller_handle = "Bob",
    };
    size_t written = 0;
    uint8_t call_buf[BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_INCOMING_CALL_BODY_SIZE];
    ble_result_t rc = ble_encode_incoming_call(&call, BLE_FLAG_ALERT,
                                                call_buf, sizeof(call_buf),
                                                &written);
    TEST_ASSERT_EQUAL(BLE_OK, rc);

    ble_server_handle_screen_data(call_buf, written, &s_fsm, &s_cache, 200);

    /* FSM should be in ALERT_OVERLAY showing the call screen. */
    TEST_ASSERT_EQUAL(SCREEN_FSM_ALERT_OVERLAY, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_INCOMING_CALL, s_fsm.current_display_id);
    /* Active screen is still speed — it remembers what to return to. */
    TEST_ASSERT_EQUAL(BLE_SCREEN_SPEED_HEADING, s_fsm.active_screen_id);

    /* Clear the alert. */
    ble_control_payload_t clear_ctrl = {
        .command    = BLE_CONTROL_CMD_CLEAR_ALERT,
        .screen_id  = 0,
        .brightness = 0,
    };
    uint8_t clear_buf[BLE_CONTROL_PAYLOAD_SIZE];
    written = 0;
    rc = ble_encode_control(&clear_ctrl, clear_buf, sizeof(clear_buf), &written);
    TEST_ASSERT_EQUAL(BLE_OK, rc);

    ble_server_handle_control(clear_buf, written, &s_fsm);

    /* FSM should return to ACTIVE with speed as the displayed screen. */
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_SPEED_HEADING, s_fsm.active_screen_id);
    TEST_ASSERT_EQUAL(BLE_SCREEN_SPEED_HEADING, s_fsm.current_display_id);
}

/* ------------------------------------------------------------------ */
/* Integration scenario 4: sleep and wake                              */
/* ------------------------------------------------------------------ */

static void test_sleep_and_wake(void)
{
    /* Connect and feed clock data. */
    ble_server_handle_connection_change(true, &s_reconnect, 100);

    uint8_t buf[128];
    size_t len = encode_clock(buf, sizeof(buf), 0);
    ble_server_handle_screen_data(buf, len, &s_fsm, &s_cache, 200);

    /* Sleep command. */
    ble_control_payload_t sleep_ctrl = {
        .command    = BLE_CONTROL_CMD_SLEEP,
        .screen_id  = 0,
        .brightness = 0,
    };
    uint8_t ctrl_buf[BLE_CONTROL_PAYLOAD_SIZE];
    size_t written = 0;
    ble_result_t rc = ble_encode_control(&sleep_ctrl, ctrl_buf,
                                          sizeof(ctrl_buf), &written);
    TEST_ASSERT_EQUAL(BLE_OK, rc);

    ble_server_handle_control(ctrl_buf, written, &s_fsm);
    TEST_ASSERT_EQUAL(SCREEN_FSM_SLEEP, s_fsm.state);

    /* Data arriving during sleep is cached but FSM stays sleeping. */
    len = encode_clock(buf, sizeof(buf), 0);
    ble_server_handle_screen_data(buf, len, &s_fsm, &s_cache, 400);
    TEST_ASSERT_EQUAL(SCREEN_FSM_SLEEP, s_fsm.state);

    const ble_payload_cache_entry_t *entry =
        ble_payload_cache_get(&s_cache, BLE_SCREEN_CLOCK);
    TEST_ASSERT_NOT_NULL(entry);
    TEST_ASSERT_EQUAL(400u, entry->updated_ms);  /* cache was updated */

    /* Wake command. */
    ble_control_payload_t wake_ctrl = {
        .command    = BLE_CONTROL_CMD_WAKE,
        .screen_id  = 0,
        .brightness = 0,
    };
    written = 0;
    rc = ble_encode_control(&wake_ctrl, ctrl_buf, sizeof(ctrl_buf), &written);
    TEST_ASSERT_EQUAL(BLE_OK, rc);

    ble_server_handle_control(ctrl_buf, written, &s_fsm);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_CLOCK, s_fsm.active_screen_id);
}

/* ------------------------------------------------------------------ */
/* Integration scenario 5: multiple screen data ignores non-active     */
/* ------------------------------------------------------------------ */

static void test_non_active_screen_data_ignored_by_fsm(void)
{
    /* Active screen is clock (default). Feed speed data. */
    uint8_t buf[128];
    size_t len = encode_speed(buf, sizeof(buf), 0);
    ble_server_handle_screen_data(buf, len, &s_fsm, &s_cache, 100);

    /* FSM should still display clock — speed data is for a non-active screen. */
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_CLOCK, s_fsm.current_display_id);

    /* But the speed data should be cached for later use. */
    const ble_payload_cache_entry_t *entry =
        ble_payload_cache_get(&s_cache, BLE_SCREEN_SPEED_HEADING);
    TEST_ASSERT_NOT_NULL(entry);
    TEST_ASSERT_TRUE(entry->present);
    TEST_ASSERT_EQUAL(BLE_PROTOCOL_SPEED_HEADING_BODY_SIZE, entry->length);
}

/* ------------------------------------------------------------------ */
/* Runner                                                              */
/* ------------------------------------------------------------------ */

int main(void)
{
    UNITY_BEGIN();

    RUN_TEST(test_boot_clock_then_switch_to_speed);
    RUN_TEST(test_disconnect_reconnect_cycle);
    RUN_TEST(test_alert_overlay_and_clear);
    RUN_TEST(test_sleep_and_wake);
    RUN_TEST(test_non_active_screen_data_ignored_by_fsm);

    return UNITY_END();
}
