/*
 * Host-side Unity tests for screen_fsm.
 *
 * The behaviour table in include/screen_fsm.h spells out every state x
 * event combination. We assert each one explicitly so a regression in any
 * cell trips a named test instead of being lost in a generic "fsm_works"
 * smoke test.
 */
#include "screen_fsm.h"
#include "unity.h"

#include <stdint.h>

#define CLOCK   ((uint8_t)0x0Du)
#define COMPASS ((uint8_t)0x03u)
#define NAV     ((uint8_t)0x01u)
#define ALERT_A ((uint8_t)0x09u) /* incoming call */
#define ALERT_B ((uint8_t)0x08u) /* blitzer       */

void setUp(void) {}
void tearDown(void) {}

/* ----- helpers ---------------------------------------------------------- */

static screen_fsm_t make_active(uint8_t id)
{
    screen_fsm_t fsm;
    screen_fsm_init(&fsm, id);
    return fsm;
}

static screen_fsm_t make_overlay(uint8_t active, uint8_t alert, uint8_t priority)
{
    screen_fsm_t fsm = make_active(active);
    (void)screen_fsm_handle_alert(&fsm, alert, priority);
    return fsm;
}

static screen_fsm_t make_sleeping(uint8_t active)
{
    screen_fsm_t fsm = make_active(active);
    (void)screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_SLEEP, 0);
    return fsm;
}

/* ----- init ------------------------------------------------------------- */

static void test_init_sets_active(void)
{
    screen_fsm_t fsm;
    screen_fsm_init(&fsm, CLOCK);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(CLOCK, fsm.active_screen_id);
    TEST_ASSERT_EQUAL_UINT8(CLOCK, fsm.current_display_id);
    TEST_ASSERT_EQUAL_UINT8(0u, fsm.alert_priority);
}

/* ----- ACTIVE state ----------------------------------------------------- */

static void test_active_set_active_renders_new_screen(void)
{
    screen_fsm_t fsm = make_active(CLOCK);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_SET_ACTIVE, COMPASS);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_RENDER_SCREEN, out.kind);
    TEST_ASSERT_EQUAL_UINT8(COMPASS, out.screen_id);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(COMPASS, fsm.active_screen_id);
    TEST_ASSERT_EQUAL_UINT8(COMPASS, fsm.current_display_id);
}

static void test_active_alert_incoming_enters_overlay(void)
{
    screen_fsm_t fsm = make_active(CLOCK);
    screen_fsm_outcome_t out = screen_fsm_handle_alert(&fsm, ALERT_A, 5);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_RENDER_SCREEN, out.kind);
    TEST_ASSERT_EQUAL_UINT8(ALERT_A, out.screen_id);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ALERT_OVERLAY, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(CLOCK, fsm.active_screen_id);
    TEST_ASSERT_EQUAL_UINT8(ALERT_A, fsm.current_display_id);
    TEST_ASSERT_EQUAL_UINT8(5u, fsm.alert_priority);
}

static void test_active_clear_alert_is_noop(void)
{
    screen_fsm_t fsm = make_active(CLOCK);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_CLEAR_ALERT, 0);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, fsm.state);
}

static void test_active_sleep_dims(void)
{
    screen_fsm_t fsm = make_active(CLOCK);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_SLEEP, 0);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_DIM_DISPLAY, out.kind);
    TEST_ASSERT_EQUAL(SCREEN_FSM_SLEEP, fsm.state);
}

static void test_active_wake_is_noop(void)
{
    screen_fsm_t fsm = make_active(CLOCK);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_WAKE, 0);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, fsm.state);
}

static void test_active_data_arrived_for_active_renders(void)
{
    screen_fsm_t fsm = make_active(CLOCK);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_DATA_ARRIVED, CLOCK);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_RENDER_SCREEN, out.kind);
    TEST_ASSERT_EQUAL_UINT8(CLOCK, out.screen_id);
}

static void test_active_data_arrived_for_other_is_ignored(void)
{
    screen_fsm_t fsm = make_active(CLOCK);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_DATA_ARRIVED, COMPASS);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL_UINT8(CLOCK, fsm.current_display_id);
}

/* ----- ALERT_OVERLAY state --------------------------------------------- */

static void test_overlay_set_active_updates_return_to_only(void)
{
    screen_fsm_t fsm = make_overlay(CLOCK, ALERT_A, 5);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_SET_ACTIVE, NAV);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ALERT_OVERLAY, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(NAV, fsm.active_screen_id);
    TEST_ASSERT_EQUAL_UINT8(ALERT_A, fsm.current_display_id);
}

static void test_overlay_alert_higher_priority_swaps(void)
{
    screen_fsm_t fsm = make_overlay(CLOCK, ALERT_A, 5);
    screen_fsm_outcome_t out = screen_fsm_handle_alert(&fsm, ALERT_B, 9);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_RENDER_SCREEN, out.kind);
    TEST_ASSERT_EQUAL_UINT8(ALERT_B, out.screen_id);
    TEST_ASSERT_EQUAL_UINT8(9u, fsm.alert_priority);
    TEST_ASSERT_EQUAL_UINT8(ALERT_B, fsm.current_display_id);
}

static void test_overlay_alert_equal_priority_is_ignored(void)
{
    screen_fsm_t fsm = make_overlay(CLOCK, ALERT_A, 5);
    screen_fsm_outcome_t out = screen_fsm_handle_alert(&fsm, ALERT_B, 5);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL_UINT8(ALERT_A, fsm.current_display_id);
    TEST_ASSERT_EQUAL_UINT8(5u, fsm.alert_priority);
}

static void test_overlay_alert_lower_priority_is_ignored(void)
{
    screen_fsm_t fsm = make_overlay(CLOCK, ALERT_A, 5);
    screen_fsm_outcome_t out = screen_fsm_handle_alert(&fsm, ALERT_B, 1);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL_UINT8(ALERT_A, fsm.current_display_id);
}

static void test_overlay_clear_returns_to_active(void)
{
    screen_fsm_t fsm = make_overlay(CLOCK, ALERT_A, 5);
    /* Mid-overlay the user picked NAV; we should return to NAV. */
    (void)screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_SET_ACTIVE, NAV);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_CLEAR_ALERT, 0);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_RENDER_SCREEN, out.kind);
    TEST_ASSERT_EQUAL_UINT8(NAV, out.screen_id);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(0u, fsm.alert_priority);
}

static void test_overlay_sleep_dims(void)
{
    screen_fsm_t fsm = make_overlay(CLOCK, ALERT_A, 5);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_SLEEP, 0);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_DIM_DISPLAY, out.kind);
    TEST_ASSERT_EQUAL(SCREEN_FSM_SLEEP, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(0u, fsm.alert_priority);
}

static void test_overlay_wake_is_noop(void)
{
    screen_fsm_t fsm = make_overlay(CLOCK, ALERT_A, 5);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_WAKE, 0);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ALERT_OVERLAY, fsm.state);
}

static void test_overlay_data_arrived_is_ignored(void)
{
    screen_fsm_t fsm = make_overlay(CLOCK, ALERT_A, 5);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_DATA_ARRIVED, CLOCK);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL_UINT8(ALERT_A, fsm.current_display_id);
}

/* ----- SLEEP state ----------------------------------------------------- */

static void test_sleep_wake_renders_active(void)
{
    screen_fsm_t fsm = make_sleeping(CLOCK);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_WAKE, 0);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_WAKE_DISPLAY, out.kind);
    TEST_ASSERT_EQUAL_UINT8(CLOCK, out.screen_id);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTIVE, fsm.state);
}

static void test_sleep_set_active_remembers_only(void)
{
    screen_fsm_t fsm = make_sleeping(CLOCK);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_SET_ACTIVE, NAV);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL(SCREEN_FSM_SLEEP, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(NAV, fsm.active_screen_id);

    /* On wake, the new screen is what gets rendered. */
    screen_fsm_outcome_t wake_out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_WAKE, 0);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_WAKE_DISPLAY, wake_out.kind);
    TEST_ASSERT_EQUAL_UINT8(NAV, wake_out.screen_id);
}

static void test_sleep_sleep_again_is_noop(void)
{
    screen_fsm_t fsm = make_sleeping(CLOCK);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_SLEEP, 0);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL(SCREEN_FSM_SLEEP, fsm.state);
}

static void test_sleep_clear_alert_is_noop(void)
{
    screen_fsm_t fsm = make_sleeping(CLOCK);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_CONTROL_CLEAR_ALERT, 0);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
}

static void test_sleep_alert_incoming_is_ignored(void)
{
    screen_fsm_t fsm = make_sleeping(CLOCK);
    screen_fsm_outcome_t out = screen_fsm_handle_alert(&fsm, ALERT_A, 9);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL(SCREEN_FSM_SLEEP, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(0u, fsm.alert_priority);
}

static void test_sleep_data_arrived_is_ignored(void)
{
    screen_fsm_t fsm = make_sleeping(CLOCK);
    screen_fsm_outcome_t out =
        screen_fsm_handle(&fsm, SCREEN_FSM_EVT_DATA_ARRIVED, CLOCK);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);
    TEST_ASSERT_EQUAL(SCREEN_FSM_SLEEP, fsm.state);
}

/* ----- null safety ----------------------------------------------------- */

static void test_null_fsm_returns_none(void)
{
    screen_fsm_outcome_t out =
        screen_fsm_handle(NULL, SCREEN_FSM_EVT_CONTROL_WAKE, 0);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, out.kind);

    screen_fsm_outcome_t alert_out = screen_fsm_handle_alert(NULL, ALERT_A, 1);
    TEST_ASSERT_EQUAL(SCREEN_FSM_ACTION_NONE, alert_out.kind);

    screen_fsm_init(NULL, CLOCK);
}

/* ----------------------------------------------------------------------- */

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_init_sets_active);

    RUN_TEST(test_active_set_active_renders_new_screen);
    RUN_TEST(test_active_alert_incoming_enters_overlay);
    RUN_TEST(test_active_clear_alert_is_noop);
    RUN_TEST(test_active_sleep_dims);
    RUN_TEST(test_active_wake_is_noop);
    RUN_TEST(test_active_data_arrived_for_active_renders);
    RUN_TEST(test_active_data_arrived_for_other_is_ignored);

    RUN_TEST(test_overlay_set_active_updates_return_to_only);
    RUN_TEST(test_overlay_alert_higher_priority_swaps);
    RUN_TEST(test_overlay_alert_equal_priority_is_ignored);
    RUN_TEST(test_overlay_alert_lower_priority_is_ignored);
    RUN_TEST(test_overlay_clear_returns_to_active);
    RUN_TEST(test_overlay_sleep_dims);
    RUN_TEST(test_overlay_wake_is_noop);
    RUN_TEST(test_overlay_data_arrived_is_ignored);

    RUN_TEST(test_sleep_wake_renders_active);
    RUN_TEST(test_sleep_set_active_remembers_only);
    RUN_TEST(test_sleep_sleep_again_is_noop);
    RUN_TEST(test_sleep_clear_alert_is_noop);
    RUN_TEST(test_sleep_alert_incoming_is_ignored);
    RUN_TEST(test_sleep_data_arrived_is_ignored);

    RUN_TEST(test_null_fsm_returns_none);

    return UNITY_END();
}
