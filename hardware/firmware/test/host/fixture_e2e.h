/*
 * fixture_e2e.h — Fixture-driven E2E test harness for the BLE-to-screen
 * pipeline.
 *
 * Loads golden .bin fixtures from protocol/fixtures/, feeds them through
 * ble_server_handle_screen_data(), and asserts FSM state + payload cache
 * contents. Covers the full firmware reception path in one call.
 *
 * Two modes:
 *   - fixture_e2e_assert_auto(): auto-derives expected FSM state from the
 *     fixture's header flags. One-liner for the 80% case.
 *   - fixture_e2e_assert(): caller supplies explicit expectations for
 *     edge cases (e.g., testing from SLEEP state).
 */
#ifndef FIXTURE_E2E_H
#define FIXTURE_E2E_H

#include "ble_protocol.h"
#include "ble_reconnect.h"
#include "ble_server_handlers.h"
#include "screen_fsm.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Expected FSM + cache state after feeding one fixture through the pipeline.
 */
typedef struct {
    screen_fsm_state_t expected_fsm_state;
    uint8_t expected_display_id;
    uint8_t expected_active_id;
} fixture_e2e_expect_t;

/*
 * Mutable test context. Pass the same context across sequential calls to
 * test multi-step sequences on a shared FSM + cache.
 */
typedef struct {
    screen_fsm_t fsm;
    ble_payload_cache_t cache;
    uint32_t now_ms;
} fixture_e2e_ctx_t;

/* Initialize context with BLE_SCREEN_CLOCK as the default active screen. */
void fixture_e2e_reset(fixture_e2e_ctx_t *ctx);

/* Initialize context with a specific active screen. */
void fixture_e2e_reset_with(fixture_e2e_ctx_t *ctx, uint8_t initial_active);

/*
 * Load a .bin fixture, feed it through ble_server_handle_screen_data(),
 * and assert:
 *   1. FSM state, current_display_id, active_screen_id match `expect`.
 *   2. Cache has an entry for the fixture's screen_id.
 *   3. Cached body bytes match the body portion of the .bin.
 *   4. Cache timestamp equals ctx->now_ms.
 *
 * Advances ctx->now_ms by 100 after the call.
 */
void fixture_e2e_assert(fixture_e2e_ctx_t *ctx, const char *fixture_name,
                        const fixture_e2e_expect_t *expect);

/*
 * Same as fixture_e2e_assert but auto-derives expected FSM state:
 *   - ALERT flag set  -> ALERT_OVERLAY, display = fixture screen_id
 *   - no ALERT, screen == active -> ACTIVE, display = fixture screen_id
 *   - no ALERT, screen != active -> ACTIVE, display unchanged
 *
 * Use fixture_e2e_assert() when auto-derivation would be wrong (e.g.,
 * feeding data while FSM is in SLEEP state).
 */
void fixture_e2e_assert_auto(fixture_e2e_ctx_t *ctx, const char *fixture_name);

/*
 * Feed a control command fixture (from protocol/fixtures/control/valid/)
 * and assert FSM state.
 */
void fixture_e2e_control(fixture_e2e_ctx_t *ctx, const char *control_name,
                         const fixture_e2e_expect_t *expect);

/*
 * Entry for the auto-generated fixture table. Maps a fixture name to its
 * screen_id and whether it carries the ALERT flag.
 */
typedef struct {
    const char *name;
    uint8_t screen_id;
    bool has_alert;
} fixture_e2e_entry_t;

#ifdef __cplusplus
}
#endif

#endif /* FIXTURE_E2E_H */
