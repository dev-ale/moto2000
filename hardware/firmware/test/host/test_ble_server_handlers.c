/*
 * test_ble_server_handlers.c — Unity host tests for the pure-C dispatch
 * layer in ble_server_handlers.c.
 *
 * These tests encode real BLE payloads using the ble_protocol encoder,
 * feed them through the handler functions, and verify the downstream
 * screen_fsm / ble_reconnect / payload_cache state.
 */

#include "unity.h"

#include "ble_protocol.h"
#include "ble_reconnect.h"
#include "ble_server_handlers.h"
#include "screen_fsm.h"

#include <string.h>

/* Shared test state. */
static screen_fsm_t         s_fsm;
static ble_payload_cache_t  s_cache;
static ble_reconnect_fsm_t  s_reconnect;

void setUp(void)
{
    screen_fsm_init(&s_fsm, BLE_SCREEN_CLOCK);
    ble_payload_cache_init(&s_cache);
    ble_reconnect_init(&s_reconnect);
}

void tearDown(void) {}

/* ----------------------------------------------------------------------- */
/* handle_screen_data                                                       */
/* ----------------------------------------------------------------------- */

static void test_screen_data_clock_updates_cache_and_fsm(void)
{
    /* Encode a clock payload (no ALERT flag). */
    ble_clock_data_t clk = {
        .unix_time         = 1700000000,
        .tz_offset_minutes = 60,
        .is_24h            = true,
    };

    uint8_t buf[BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_CLOCK_BODY_SIZE];
    size_t written = 0;
    ble_result_t rc = ble_encode_clock(&clk, 0, buf, sizeof(buf), &written);
    TEST_ASSERT_EQUAL(BLE_OK, rc);

    ble_server_handle_screen_data(buf, written, &s_fsm, &s_cache, 1000);

    /* The FSM should have received DATA_ARRIVED for the clock screen.
     * Since clock (0x0D) is the initial active screen, it triggers a
     * re-render. */
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_CLOCK, s_fsm.current_display_id);

    /* The cache should have the clock body stored. */
    const ble_payload_cache_entry_t *entry =
        ble_payload_cache_get(&s_cache, BLE_SCREEN_CLOCK);
    TEST_ASSERT_NOT_NULL(entry);
    TEST_ASSERT_TRUE(entry->present);
    TEST_ASSERT_EQUAL(BLE_PROTOCOL_CLOCK_BODY_SIZE, entry->length);
    TEST_ASSERT_EQUAL(1000u, entry->updated_ms);
}

static void test_screen_data_alert_triggers_alert_incoming(void)
{
    /* Encode an incoming call payload with the ALERT flag. */
    ble_incoming_call_data_t call = {
        .call_state = BLE_CALL_INCOMING,
        .caller_handle = "Alice",
    };

    uint8_t buf[BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_INCOMING_CALL_BODY_SIZE];
    size_t written = 0;
    ble_result_t rc = ble_encode_incoming_call(&call, BLE_FLAG_ALERT,
                                                buf, sizeof(buf), &written);
    TEST_ASSERT_EQUAL(BLE_OK, rc);

    ble_server_handle_screen_data(buf, written, &s_fsm, &s_cache, 2000);

    /* The FSM should be in ALERT_OVERLAY state displaying the call screen. */
    TEST_ASSERT_EQUAL(SCREEN_FSM_ALERT_OVERLAY, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_INCOMING_CALL, s_fsm.current_display_id);

    /* Cache should have the incoming call body. */
    const ble_payload_cache_entry_t *entry =
        ble_payload_cache_get(&s_cache, BLE_SCREEN_INCOMING_CALL);
    TEST_ASSERT_NOT_NULL(entry);
    TEST_ASSERT_TRUE(entry->present);
    TEST_ASSERT_EQUAL(BLE_PROTOCOL_INCOMING_CALL_BODY_SIZE, entry->length);
}

/* ----------------------------------------------------------------------- */
/* handle_control                                                           */
/* ----------------------------------------------------------------------- */

static void test_control_set_active_drives_fsm(void)
{
    /* Encode SET_ACTIVE_SCREEN for navigation. */
    ble_control_payload_t ctrl = {
        .command   = BLE_CONTROL_CMD_SET_ACTIVE_SCREEN,
        .screen_id = BLE_SCREEN_NAVIGATION,
        .brightness = 0,
    };
    uint8_t buf[BLE_CONTROL_PAYLOAD_SIZE];
    size_t written = 0;
    ble_result_t rc = ble_encode_control(&ctrl, buf, sizeof(buf), &written);
    TEST_ASSERT_EQUAL(BLE_OK, rc);

    ble_server_handle_control(buf, written, &s_fsm);

    /* FSM should now have navigation as the active screen. */
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, s_fsm.state);
    TEST_ASSERT_EQUAL(BLE_SCREEN_NAVIGATION, s_fsm.active_screen_id);
    TEST_ASSERT_EQUAL(BLE_SCREEN_NAVIGATION, s_fsm.current_display_id);
}

static void test_control_sleep_drives_fsm(void)
{
    ble_control_payload_t ctrl = {
        .command    = BLE_CONTROL_CMD_SLEEP,
        .screen_id  = 0,
        .brightness = 0,
    };
    uint8_t buf[BLE_CONTROL_PAYLOAD_SIZE];
    size_t written = 0;
    ble_result_t rc = ble_encode_control(&ctrl, buf, sizeof(buf), &written);
    TEST_ASSERT_EQUAL(BLE_OK, rc);

    ble_server_handle_control(buf, written, &s_fsm);

    TEST_ASSERT_EQUAL(SCREEN_FSM_SLEEP, s_fsm.state);
}

/* ----------------------------------------------------------------------- */
/* handle_connection_change                                                 */
/* ----------------------------------------------------------------------- */

static void test_connection_change_connect(void)
{
    ble_server_handle_connection_change(true, &s_reconnect, 500);
    TEST_ASSERT_EQUAL(BLE_RC_CONNECTED, s_reconnect.state);
}

static void test_connection_change_disconnect(void)
{
    /* First connect, then disconnect. */
    ble_server_handle_connection_change(true, &s_reconnect, 500);
    TEST_ASSERT_EQUAL(BLE_RC_CONNECTED, s_reconnect.state);

    ble_server_handle_connection_change(false, &s_reconnect, 600);
    /* After disconnect from CONNECTED the FSM should transition. */
    TEST_ASSERT_TRUE(s_reconnect.state != BLE_RC_CONNECTED);
}

/* ----------------------------------------------------------------------- */
/* Runner                                                                   */
/* ----------------------------------------------------------------------- */

int main(void)
{
    UNITY_BEGIN();

    RUN_TEST(test_screen_data_clock_updates_cache_and_fsm);
    RUN_TEST(test_screen_data_alert_triggers_alert_incoming);
    RUN_TEST(test_control_set_active_drives_fsm);
    RUN_TEST(test_control_sleep_drives_fsm);
    RUN_TEST(test_connection_change_connect);
    RUN_TEST(test_connection_change_disconnect);

    return UNITY_END();
}
