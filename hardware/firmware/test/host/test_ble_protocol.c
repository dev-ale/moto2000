/*
 * Host-side Unity tests for the ble_protocol component.
 *
 * These tests exercise the same golden fixtures as the Swift BLEProtocol
 * package. If this binary decodes a fixture differently from Swift, the
 * wire format has drifted — fix the codec, not the test.
 *
 * Fixture lookup uses the SCRAMSCREEN_FIXTURES_DIR define set by the CMake
 * build so the binary finds protocol/fixtures/ regardless of the working
 * directory.
 */

#include "ble_protocol.h"
#include "unity.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef SCRAMSCREEN_FIXTURES_DIR
#error "SCRAMSCREEN_FIXTURES_DIR must be defined by the build"
#endif

#define MAX_FIXTURE_BYTES 256

typedef struct {
    uint8_t bytes[MAX_FIXTURE_BYTES];
    size_t  length;
} fixture_blob_t;

void setUp(void) {}
void tearDown(void) {}

/* ------------------------------------------------------------------------- */
/*                          fixture file loading                             */
/* ------------------------------------------------------------------------- */

static bool load_fixture(const char *subdir, const char *name, fixture_blob_t *out)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/%s/%s.bin", SCRAMSCREEN_FIXTURES_DIR, subdir, name);
    FILE *fp = fopen(path, "rb");
    if (fp == NULL) {
        fprintf(stderr, "cannot open fixture %s\n", path);
        return false;
    }
    out->length = fread(out->bytes, 1, sizeof(out->bytes), fp);
    fclose(fp);
    return true;
}

/* ------------------------------------------------------------------------- */
/*                          valid fixture round trips                        */
/* ------------------------------------------------------------------------- */

static void assert_clock_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t          flags = 0xFF;
    ble_clock_data_t clock;
    const ble_result_t decoded = ble_decode_clock(blob.bytes, blob.length, &flags, &clock);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = {0};
    size_t  written  = 0;
    const ble_result_t encoded = ble_encode_clock(&clock, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void assert_nav_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t        flags = 0xFF;
    ble_nav_data_t nav;
    const ble_result_t decoded = ble_decode_nav(blob.bytes, blob.length, &flags, &nav);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = {0};
    size_t  written  = 0;
    const ble_result_t encoded = ble_encode_nav(&nav, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void test_clock_basel_winter_roundtrip(void)
{
    assert_clock_fixture_roundtrips("clock_basel_winter");
}

static void test_clock_night_mode_roundtrip(void)
{
    assert_clock_fixture_roundtrips("clock_night_mode");
}

static void test_nav_straight_roundtrip(void)
{
    assert_nav_fixture_roundtrips("nav_straight");
}

static void test_nav_sharp_left_roundtrip(void)
{
    assert_nav_fixture_roundtrips("nav_sharp_left");
}

static void test_nav_arrive_roundtrip(void)
{
    assert_nav_fixture_roundtrips("nav_arrive");
}

/* ------------------------------------------------------------------------- */
/*                  invalid fixtures — each case fails cleanly               */
/* ------------------------------------------------------------------------- */

typedef struct {
    const char  *name;
    ble_result_t expected;
} invalid_case_t;

/*
 * The expected errors mirror the JSON files under protocol/fixtures/invalid/.
 * Keep them in sync with the Swift InvalidFixtureTests mapping.
 */
static const invalid_case_t INVALID_CASES[] = {
    {"truncated_header",     BLE_ERR_TRUNCATED_HEADER},
    {"unsupported_version",  BLE_ERR_UNSUPPORTED_VERSION},
    {"nonzero_reserved",     BLE_ERR_INVALID_RESERVED},
    {"unknown_screen_id",    BLE_ERR_UNKNOWN_SCREEN_ID},
    {"body_length_mismatch", BLE_ERR_BODY_LENGTH_MISMATCH},
    {"truncated_body",       BLE_ERR_TRUNCATED_BODY},
    {"reserved_flags_set",   BLE_ERR_RESERVED_FLAGS_SET},
};

static void test_invalid_fixtures_are_rejected(void)
{
    const size_t count = sizeof(INVALID_CASES) / sizeof(INVALID_CASES[0]);
    for (size_t i = 0; i < count; ++i) {
        fixture_blob_t blob;
        TEST_ASSERT_TRUE_MESSAGE(load_fixture("invalid", INVALID_CASES[i].name, &blob),
                                  INVALID_CASES[i].name);
        ble_header_t header;
        const ble_result_t decoded = ble_decode_header(blob.bytes, blob.length, &header);
        char message[128];
        snprintf(message, sizeof(message), "fixture %s produced %s, expected %s",
                 INVALID_CASES[i].name,
                 ble_result_name(decoded),
                 ble_result_name(INVALID_CASES[i].expected));
        TEST_ASSERT_EQUAL_MESSAGE(INVALID_CASES[i].expected, decoded, message);
    }
}

/* ------------------------------------------------------------------------- */

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_clock_basel_winter_roundtrip);
    RUN_TEST(test_clock_night_mode_roundtrip);
    RUN_TEST(test_nav_straight_roundtrip);
    RUN_TEST(test_nav_sharp_left_roundtrip);
    RUN_TEST(test_nav_arrive_roundtrip);
    RUN_TEST(test_invalid_fixtures_are_rejected);
    return UNITY_END();
}
