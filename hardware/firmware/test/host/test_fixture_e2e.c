/*
 * test_fixture_e2e.c — Fixture-driven E2E tests for the full BLE-to-screen
 * pipeline: .bin fixture -> ble_server_handle_screen_data -> FSM + cache.
 *
 * Tests are organized into three groups:
 *   1. Exhaustive sweep: every valid fixture, auto-derived expectations.
 *   2. Explicit edge cases: non-active screen, alert during sleep, etc.
 *   3. Multi-step sequences: alert overlay + dismiss, sleep/wake.
 */

#include "unity.h"
#include "fixture_e2e.h"
#include "ble_protocol.h"

/* ----------------------------------------------------------------------- */
/* Fixture table — maps every valid fixture to its screen_id + alert flag.  */
/*                                                                          */
/* When you add a new fixture to protocol/fixtures/valid/, add an entry     */
/* here. (Phase 2 will auto-generate this table.)                           */
/* ----------------------------------------------------------------------- */

static const fixture_e2e_entry_t ALL_FIXTURES[] = {
    /* altitude (0x0B) */
    { "altitude_flat", BLE_SCREEN_ALTITUDE, false },
    { "altitude_mountain_pass", BLE_SCREEN_ALTITUDE, false },
    { "altitude_start", BLE_SCREEN_ALTITUDE, false },

    /* appointment (0x0C) */
    { "appointment_now", BLE_SCREEN_APPOINTMENT, false },
    { "appointment_past", BLE_SCREEN_APPOINTMENT, false },
    { "appointment_soon", BLE_SCREEN_APPOINTMENT, false },

    /* blitzer (0x08) — ALERT */
    { "blitzer_fixed_500m", BLE_SCREEN_BLITZER, true },
    { "blitzer_mobile_close", BLE_SCREEN_BLITZER, true },
    { "blitzer_section", BLE_SCREEN_BLITZER, true },
    { "blitzer_unknown_limit", BLE_SCREEN_BLITZER, true },

    /* incomingCall (0x09) — ALERT for incoming/connected, not ended */
    { "call_connected", BLE_SCREEN_INCOMING_CALL, true },
    { "call_incoming", BLE_SCREEN_INCOMING_CALL, true },
    { "call_ended", BLE_SCREEN_INCOMING_CALL, false },

    /* clock (0x0D) */
    { "clock_basel_winter", BLE_SCREEN_CLOCK, false },
    { "clock_night_mode", BLE_SCREEN_CLOCK, false },

    /* compass (0x03) */
    { "compass_east_true", BLE_SCREEN_COMPASS, false },
    { "compass_north_magnetic", BLE_SCREEN_COMPASS, false },
    { "compass_north_magnetic_night", BLE_SCREEN_COMPASS, false },
    { "compass_southwest_unknown_true", BLE_SCREEN_COMPASS, false },

    /* fuelEstimate (0x0A) */
    { "fuel_full_tank", BLE_SCREEN_FUEL_ESTIMATE, false },
    { "fuel_half_tank", BLE_SCREEN_FUEL_ESTIMATE, false },
    { "fuel_low", BLE_SCREEN_FUEL_ESTIMATE, false },

    /* leanAngle (0x07) */
    { "lean_hard_left", BLE_SCREEN_LEAN_ANGLE, false },
    { "lean_moderate_right", BLE_SCREEN_LEAN_ANGLE, false },
    { "lean_racetrack", BLE_SCREEN_LEAN_ANGLE, false },
    { "lean_upright", BLE_SCREEN_LEAN_ANGLE, false },

    /* music (0x06) */
    { "music_long_titles", BLE_SCREEN_MUSIC, false },
    { "music_paused", BLE_SCREEN_MUSIC, false },
    { "music_playing", BLE_SCREEN_MUSIC, false },
    { "music_unknown_duration", BLE_SCREEN_MUSIC, false },

    /* navigation (0x01) */
    { "nav_arrive", BLE_SCREEN_NAVIGATION, false },
    { "nav_sharp_left", BLE_SCREEN_NAVIGATION, false },
    { "nav_straight", BLE_SCREEN_NAVIGATION, false },
    { "nav_straight_night", BLE_SCREEN_NAVIGATION, false },

    /* speedHeading (0x02) */
    { "speed_highway_120kmh", BLE_SCREEN_SPEED_HEADING, false },
    { "speed_stationary", BLE_SCREEN_SPEED_HEADING, false },
    { "speed_urban_45kmh", BLE_SCREEN_SPEED_HEADING, false },
    { "speed_urban_45kmh_night", BLE_SCREEN_SPEED_HEADING, false },

    /* tripStats (0x05) */
    { "trip_stats_city_loop", BLE_SCREEN_TRIP_STATS, false },
    { "trip_stats_fresh", BLE_SCREEN_TRIP_STATS, false },
    { "trip_stats_highway", BLE_SCREEN_TRIP_STATS, false },

    /* weather (0x04) */
    { "weather_alps_snow", BLE_SCREEN_WEATHER, false },
    { "weather_basel_clear", BLE_SCREEN_WEATHER, false },
    { "weather_cold_fog", BLE_SCREEN_WEATHER, false },
    { "weather_paris_rain", BLE_SCREEN_WEATHER, false },
    { "weather_thunderstorm", BLE_SCREEN_WEATHER, false },

    { NULL, 0, false }, /* sentinel */
};

static fixture_e2e_ctx_t ctx;

void setUp(void)
{
    fixture_e2e_reset(&ctx);
}
void tearDown(void) {}

/* ======================================================================= */
/* 1. Exhaustive sweep — every fixture through the full pipeline            */
/* ======================================================================= */

/*
 * For non-alert fixtures: set active screen = fixture's screen, so the FSM
 * renders it (the common case on a real device).
 * For alert fixtures: leave active at clock, so the alert overlays it.
 *
 * fixture_e2e_assert_auto handles both cases via header flag inspection.
 */
static void test_all_fixtures_active_screen(void)
{
    for (const fixture_e2e_entry_t *f = ALL_FIXTURES; f->name != NULL; f++) {
        fixture_e2e_ctx_t local;
        if (f->has_alert) {
            /* Alerts overlay whatever is active. Use clock as the base. */
            fixture_e2e_reset_with(&local, BLE_SCREEN_CLOCK);
        } else {
            /* Regular data: set active = fixture's screen. */
            fixture_e2e_reset_with(&local, f->screen_id);
        }
        fixture_e2e_assert_auto(&local, f->name);
    }
}

/* ======================================================================= */
/* 2. Edge cases with explicit expectations                                 */
/* ======================================================================= */

/* Data arriving for a non-active screen: FSM stays on active, but cache
 * is still updated. */
static void test_data_for_nonactive_screen(void)
{
    fixture_e2e_reset_with(&ctx, BLE_SCREEN_CLOCK);

    fixture_e2e_assert(&ctx, "speed_urban_45kmh",
                       &(fixture_e2e_expect_t){
                           .expected_fsm_state = SCREEN_FSM_ACTIVE,
                           .expected_display_id = BLE_SCREEN_CLOCK, /* unchanged */
                           .expected_active_id = BLE_SCREEN_CLOCK,
                       });
}

/* Multiple non-active screens: cache accumulates entries for all of them. */
static void test_cache_accumulates_nonactive(void)
{
    fixture_e2e_reset_with(&ctx, BLE_SCREEN_CLOCK);

    fixture_e2e_assert(&ctx, "speed_urban_45kmh",
                       &(fixture_e2e_expect_t){
                           .expected_fsm_state = SCREEN_FSM_ACTIVE,
                           .expected_display_id = BLE_SCREEN_CLOCK,
                           .expected_active_id = BLE_SCREEN_CLOCK,
                       });

    fixture_e2e_assert(&ctx, "weather_basel_clear",
                       &(fixture_e2e_expect_t){
                           .expected_fsm_state = SCREEN_FSM_ACTIVE,
                           .expected_display_id = BLE_SCREEN_CLOCK,
                           .expected_active_id = BLE_SCREEN_CLOCK,
                       });

    /* Verify both cache entries exist. */
    const ble_payload_cache_entry_t *speed_entry =
        ble_payload_cache_get(&ctx.cache, BLE_SCREEN_SPEED_HEADING);
    TEST_ASSERT_NOT_NULL(speed_entry);
    TEST_ASSERT_TRUE(speed_entry->present);

    const ble_payload_cache_entry_t *weather_entry =
        ble_payload_cache_get(&ctx.cache, BLE_SCREEN_WEATHER);
    TEST_ASSERT_NOT_NULL(weather_entry);
    TEST_ASSERT_TRUE(weather_entry->present);
}

/* Alert with blitzer: should trigger ALERT_OVERLAY even when active screen
 * is different. */
static void test_blitzer_alert_overlays_nav(void)
{
    fixture_e2e_reset_with(&ctx, BLE_SCREEN_NAVIGATION);

    fixture_e2e_assert(&ctx, "blitzer_fixed_500m",
                       &(fixture_e2e_expect_t){
                           .expected_fsm_state = SCREEN_FSM_ALERT_OVERLAY,
                           .expected_display_id = BLE_SCREEN_BLITZER,
                           .expected_active_id = BLE_SCREEN_NAVIGATION, /* preserved */
                       });
}

/* ======================================================================= */
/* 3. Multi-step sequences                                                  */
/* ======================================================================= */

/* Nav active -> incoming call alert -> clear alert -> back to nav. */
static void test_sequence_alert_overlay_and_dismiss(void)
{
    fixture_e2e_reset_with(&ctx, BLE_SCREEN_NAVIGATION);

    /* Step 1: nav data arrives for active screen. */
    fixture_e2e_assert(&ctx, "nav_straight",
                       &(fixture_e2e_expect_t){
                           .expected_fsm_state = SCREEN_FSM_ACTIVE,
                           .expected_display_id = BLE_SCREEN_NAVIGATION,
                           .expected_active_id = BLE_SCREEN_NAVIGATION,
                       });

    /* Step 2: incoming call alert. */
    fixture_e2e_assert(&ctx, "call_incoming",
                       &(fixture_e2e_expect_t){
                           .expected_fsm_state = SCREEN_FSM_ALERT_OVERLAY,
                           .expected_display_id = BLE_SCREEN_INCOMING_CALL,
                           .expected_active_id = BLE_SCREEN_NAVIGATION, /* preserved */
                       });

    /* Step 3: clear alert -> back to nav. */
    fixture_e2e_control(&ctx, "clear_alert",
                        &(fixture_e2e_expect_t){
                            .expected_fsm_state = SCREEN_FSM_ACTIVE,
                            .expected_display_id = BLE_SCREEN_NAVIGATION,
                            .expected_active_id = BLE_SCREEN_NAVIGATION,
                        });
}

/* Sleep -> data arrives (cached, no render) -> wake -> verify cache. */
static void test_sequence_sleep_data_wake(void)
{
    fixture_e2e_reset_with(&ctx, BLE_SCREEN_SPEED_HEADING);

    /* Step 1: put FSM to sleep via control. */
    fixture_e2e_control(&ctx, "sleep",
                        &(fixture_e2e_expect_t){
                            .expected_fsm_state = SCREEN_FSM_SLEEP,
                            .expected_display_id = BLE_SCREEN_SPEED_HEADING,
                            .expected_active_id = BLE_SCREEN_SPEED_HEADING,
                        });

    /* Step 2: speed data arrives while sleeping. FSM stays in SLEEP.
     * Use explicit assert because auto would assume ACTIVE. */
    fixture_e2e_assert(&ctx, "speed_urban_45kmh",
                       &(fixture_e2e_expect_t){
                           .expected_fsm_state = SCREEN_FSM_SLEEP,
                           .expected_display_id = BLE_SCREEN_SPEED_HEADING,
                           .expected_active_id = BLE_SCREEN_SPEED_HEADING,
                       });

    /* Step 3: wake -> should go back to ACTIVE and render speed. */
    fixture_e2e_control(&ctx, "wake",
                        &(fixture_e2e_expect_t){
                            .expected_fsm_state = SCREEN_FSM_ACTIVE,
                            .expected_display_id = BLE_SCREEN_SPEED_HEADING,
                            .expected_active_id = BLE_SCREEN_SPEED_HEADING,
                        });

    /* Verify the speed data from step 2 is still in cache. */
    const ble_payload_cache_entry_t *entry =
        ble_payload_cache_get(&ctx.cache, BLE_SCREEN_SPEED_HEADING);
    TEST_ASSERT_NOT_NULL(entry);
    TEST_ASSERT_TRUE(entry->present);
    TEST_ASSERT_EQUAL(BLE_PROTOCOL_SPEED_HEADING_BODY_SIZE, entry->length);
}

/* Switch active screen via control, then receive data for new screen. */
static void test_sequence_switch_active_then_data(void)
{
    fixture_e2e_reset_with(&ctx, BLE_SCREEN_CLOCK);

    /* Switch active to navigation. */
    fixture_e2e_control(&ctx, "set_active_nav",
                        &(fixture_e2e_expect_t){
                            .expected_fsm_state = SCREEN_FSM_ACTIVE,
                            .expected_display_id = BLE_SCREEN_NAVIGATION,
                            .expected_active_id = BLE_SCREEN_NAVIGATION,
                        });

    /* Now nav data arrives for the (now active) navigation screen. */
    fixture_e2e_assert_auto(&ctx, "nav_straight");
}

/* Higher-priority alert replaces lower-priority alert. */
static void test_sequence_alert_priority(void)
{
    fixture_e2e_reset_with(&ctx, BLE_SCREEN_CLOCK);

    /* Blitzer alert (screen_id 0x08, used as priority). */
    fixture_e2e_assert(&ctx, "blitzer_fixed_500m",
                       &(fixture_e2e_expect_t){
                           .expected_fsm_state = SCREEN_FSM_ALERT_OVERLAY,
                           .expected_display_id = BLE_SCREEN_BLITZER,
                           .expected_active_id = BLE_SCREEN_CLOCK,
                       });

    /* Incoming call alert (screen_id 0x09, higher priority). */
    fixture_e2e_assert(&ctx, "call_incoming",
                       &(fixture_e2e_expect_t){
                           .expected_fsm_state = SCREEN_FSM_ALERT_OVERLAY,
                           .expected_display_id = BLE_SCREEN_INCOMING_CALL,
                           .expected_active_id = BLE_SCREEN_CLOCK,
                       });
}

/* ----------------------------------------------------------------------- */
/* Runner                                                                   */
/* ----------------------------------------------------------------------- */

int main(void)
{
    UNITY_BEGIN();

    /* Exhaustive sweep. */
    RUN_TEST(test_all_fixtures_active_screen);

    /* Edge cases. */
    RUN_TEST(test_data_for_nonactive_screen);
    RUN_TEST(test_cache_accumulates_nonactive);
    RUN_TEST(test_blitzer_alert_overlays_nav);

    /* Multi-step sequences. */
    RUN_TEST(test_sequence_alert_overlay_and_dismiss);
    RUN_TEST(test_sequence_sleep_data_wake);
    RUN_TEST(test_sequence_switch_active_then_data);
    RUN_TEST(test_sequence_alert_priority);

    return UNITY_END();
}
