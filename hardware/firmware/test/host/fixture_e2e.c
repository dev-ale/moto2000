/*
 * fixture_e2e.c — Implementation of the fixture-driven E2E test harness.
 */

#include "fixture_e2e.h"
#include "unity.h"

#include <stdio.h>
#include <string.h>

#ifndef SCRAMSCREEN_FIXTURES_DIR
#error "SCRAMSCREEN_FIXTURES_DIR must be defined by the build"
#endif

#define E2E_MAX_BYTES 256
#define E2E_TIME_STEP 100u

/* ----------------------------------------------------------------------- */
/* Fixture loading                                                          */
/* ----------------------------------------------------------------------- */

typedef struct {
    uint8_t bytes[E2E_MAX_BYTES];
    size_t length;
} e2e_blob_t;

static bool load_bin(const char *subdir, const char *name, e2e_blob_t *out, char *err_buf,
                     size_t err_cap)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/%s/%s.bin", SCRAMSCREEN_FIXTURES_DIR, subdir, name);
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        snprintf(err_buf, err_cap, "cannot open fixture: %s", path);
        return false;
    }
    out->length = fread(out->bytes, 1, sizeof(out->bytes), fp);
    fclose(fp);
    return true;
}

/* ----------------------------------------------------------------------- */
/* Context init                                                             */
/* ----------------------------------------------------------------------- */

void fixture_e2e_reset(fixture_e2e_ctx_t *ctx)
{
    fixture_e2e_reset_with(ctx, BLE_SCREEN_CLOCK);
}

void fixture_e2e_reset_with(fixture_e2e_ctx_t *ctx, uint8_t initial_active)
{
    screen_fsm_init(&ctx->fsm, initial_active);
    ble_payload_cache_init(&ctx->cache);
    ctx->now_ms = 1000;
}

/* ----------------------------------------------------------------------- */
/* Cache body assertion                                                     */
/* ----------------------------------------------------------------------- */

static void assert_cache(const char *label, const ble_payload_cache_t *cache, uint8_t screen_id,
                         const uint8_t *expected_body, uint16_t expected_body_len,
                         uint32_t expected_timestamp)
{
    char msg[256];

    const ble_payload_cache_entry_t *entry = ble_payload_cache_get(cache, screen_id);

    snprintf(msg, sizeof(msg), "[%s] cache entry present for screen 0x%02X", label, screen_id);
    TEST_ASSERT_NOT_NULL_MESSAGE(entry, msg);
    TEST_ASSERT_TRUE_MESSAGE(entry->present, msg);

    /* The cache truncates bodies larger than BLE_PAYLOAD_CACHE_BODY_MAX. */
    uint16_t stored_len = expected_body_len;
    if (stored_len > BLE_PAYLOAD_CACHE_BODY_MAX) {
        stored_len = BLE_PAYLOAD_CACHE_BODY_MAX;
    }

    snprintf(msg, sizeof(msg), "[%s] cache body length", label);
    TEST_ASSERT_EQUAL_UINT16_MESSAGE(stored_len, entry->length, msg);

    snprintf(msg, sizeof(msg), "[%s] cache body bytes", label);
    TEST_ASSERT_EQUAL_MEMORY_MESSAGE(expected_body, entry->body, stored_len, msg);

    snprintf(msg, sizeof(msg), "[%s] cache timestamp", label);
    TEST_ASSERT_EQUAL_UINT32_MESSAGE(expected_timestamp, entry->updated_ms, msg);
}

/* ----------------------------------------------------------------------- */
/* FSM assertion                                                            */
/* ----------------------------------------------------------------------- */

static void assert_fsm(const char *label, const screen_fsm_t *fsm,
                       const fixture_e2e_expect_t *expect)
{
    char msg[256];

    snprintf(msg, sizeof(msg), "[%s] fsm.state", label);
    TEST_ASSERT_EQUAL_MESSAGE(expect->expected_fsm_state, fsm->state, msg);

    snprintf(msg, sizeof(msg), "[%s] current_display_id", label);
    TEST_ASSERT_EQUAL_MESSAGE(expect->expected_display_id, fsm->current_display_id, msg);

    snprintf(msg, sizeof(msg), "[%s] active_screen_id", label);
    TEST_ASSERT_EQUAL_MESSAGE(expect->expected_active_id, fsm->active_screen_id, msg);
}

/* ----------------------------------------------------------------------- */
/* Public: explicit expectations                                            */
/* ----------------------------------------------------------------------- */

void fixture_e2e_assert(fixture_e2e_ctx_t *ctx, const char *fixture_name,
                        const fixture_e2e_expect_t *expect)
{
    char err[512];
    e2e_blob_t blob;
    if (!load_bin("valid", fixture_name, &blob, err, sizeof(err))) {
        TEST_FAIL_MESSAGE(err);
        return;
    }

    /* Decode header to get screen_id and body pointer. */
    ble_header_t hdr;
    ble_result_t rc = ble_decode_header(blob.bytes, blob.length, &hdr);
    {
        char msg[256];
        snprintf(msg, sizeof(msg), "[%s] ble_decode_header", fixture_name);
        TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, rc, msg);
    }

    /* Feed through the full pipeline. */
    ble_server_handle_screen_data(blob.bytes, blob.length, &ctx->fsm, &ctx->cache, ctx->now_ms);

    /* Assert FSM state. */
    assert_fsm(fixture_name, &ctx->fsm, expect);

    /* Assert cache contents. */
    assert_cache(fixture_name, &ctx->cache, (uint8_t)hdr.screen_id, hdr.body, hdr.body_length,
                 ctx->now_ms);

    ctx->now_ms += E2E_TIME_STEP;
}

/* ----------------------------------------------------------------------- */
/* Public: auto-derived expectations                                        */
/* ----------------------------------------------------------------------- */

void fixture_e2e_assert_auto(fixture_e2e_ctx_t *ctx, const char *fixture_name)
{
    char err[512];
    e2e_blob_t blob;
    if (!load_bin("valid", fixture_name, &blob, err, sizeof(err))) {
        TEST_FAIL_MESSAGE(err);
        return;
    }

    /* Peek at the header to derive expectations. */
    ble_header_t hdr;
    ble_result_t rc = ble_decode_header(blob.bytes, blob.length, &hdr);
    {
        char msg[256];
        snprintf(msg, sizeof(msg), "[%s] ble_decode_header", fixture_name);
        TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, rc, msg);
    }

    uint8_t screen_id = (uint8_t)hdr.screen_id;
    bool is_alert = (hdr.flags & BLE_FLAG_ALERT) != 0;

    fixture_e2e_expect_t expect;

    if (is_alert) {
        /* Alert overlays: FSM goes to ALERT_OVERLAY, display shows alert
         * screen, active screen stays whatever it was. */
        expect.expected_fsm_state = SCREEN_FSM_ALERT_OVERLAY;
        expect.expected_display_id = screen_id;
        expect.expected_active_id = ctx->fsm.active_screen_id;
    } else if (screen_id == ctx->fsm.active_screen_id) {
        /* Data for the active screen: FSM stays ACTIVE, re-render. */
        expect.expected_fsm_state = SCREEN_FSM_ACTIVE;
        expect.expected_display_id = screen_id;
        expect.expected_active_id = screen_id;
    } else {
        /* Data for a non-active screen: FSM stays ACTIVE, display
         * unchanged, cache still updated. */
        expect.expected_fsm_state = SCREEN_FSM_ACTIVE;
        expect.expected_display_id = ctx->fsm.current_display_id;
        expect.expected_active_id = ctx->fsm.active_screen_id;
    }

    /* Feed through the full pipeline. */
    ble_server_handle_screen_data(blob.bytes, blob.length, &ctx->fsm, &ctx->cache, ctx->now_ms);

    /* Assert FSM state. */
    assert_fsm(fixture_name, &ctx->fsm, &expect);

    /* Assert cache contents. */
    assert_cache(fixture_name, &ctx->cache, screen_id, hdr.body, hdr.body_length, ctx->now_ms);

    ctx->now_ms += E2E_TIME_STEP;
}

/* ----------------------------------------------------------------------- */
/* Public: control command                                                  */
/* ----------------------------------------------------------------------- */

void fixture_e2e_control(fixture_e2e_ctx_t *ctx, const char *control_name,
                         const fixture_e2e_expect_t *expect)
{
    char err[512];
    e2e_blob_t blob;
    if (!load_bin("control/valid", control_name, &blob, err, sizeof(err))) {
        TEST_FAIL_MESSAGE(err);
        return;
    }

    ble_server_handle_control(blob.bytes, blob.length, &ctx->fsm);
    assert_fsm(control_name, &ctx->fsm, expect);

    ctx->now_ms += E2E_TIME_STEP;
}
