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
    size_t length;
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

    uint8_t flags = 0xFF;
    ble_clock_data_t clock;
    const ble_result_t decoded = ble_decode_clock(blob.bytes, blob.length, &flags, &clock);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded = ble_encode_clock(&clock, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void assert_speed_heading_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_speed_heading_data_t decoded_body;
    const ble_result_t decoded =
        ble_decode_speed_heading(blob.bytes, blob.length, &flags, &decoded_body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded =
        ble_encode_speed_heading(&decoded_body, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void assert_compass_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_compass_data_t decoded_body;
    const ble_result_t decoded = ble_decode_compass(blob.bytes, blob.length, &flags, &decoded_body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded =
        ble_encode_compass(&decoded_body, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void assert_trip_stats_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_trip_stats_data_t decoded_body;
    const ble_result_t decoded =
        ble_decode_trip_stats(blob.bytes, blob.length, &flags, &decoded_body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded =
        ble_encode_trip_stats(&decoded_body, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void assert_weather_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_weather_data_t weather;
    const ble_result_t decoded = ble_decode_weather(blob.bytes, blob.length, &flags, &weather);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded = ble_encode_weather(&weather, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void assert_music_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_music_data_t decoded_body;
    const ble_result_t decoded = ble_decode_music(blob.bytes, blob.length, &flags, &decoded_body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded = ble_encode_music(&decoded_body, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void assert_nav_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_nav_data_t nav;
    const ble_result_t decoded = ble_decode_nav(blob.bytes, blob.length, &flags, &nav);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
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

static void test_speed_urban_45_roundtrip(void)
{
    assert_speed_heading_fixture_roundtrips("speed_urban_45kmh");
}

static void test_speed_highway_120_roundtrip(void)
{
    assert_speed_heading_fixture_roundtrips("speed_highway_120kmh");
}

static void test_speed_stationary_roundtrip(void)
{
    assert_speed_heading_fixture_roundtrips("speed_stationary");
}

static void test_compass_north_magnetic_roundtrip(void)
{
    assert_compass_fixture_roundtrips("compass_north_magnetic");
}

static void test_compass_east_true_roundtrip(void)
{
    assert_compass_fixture_roundtrips("compass_east_true");
}

static void test_compass_southwest_unknown_true_roundtrip(void)
{
    assert_compass_fixture_roundtrips("compass_southwest_unknown_true");
}

static void test_trip_stats_fresh_roundtrip(void)
{
    assert_trip_stats_fixture_roundtrips("trip_stats_fresh");
}

static void test_trip_stats_city_loop_roundtrip(void)
{
    assert_trip_stats_fixture_roundtrips("trip_stats_city_loop");
}

static void test_trip_stats_highway_roundtrip(void)
{
    assert_trip_stats_fixture_roundtrips("trip_stats_highway");
}

static void test_trip_stats_speed_out_of_range_fixture_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("invalid", "trip_stats_speed_out_of_range", &blob));
    ble_trip_stats_data_t body;
    const ble_result_t result = ble_decode_trip_stats(blob.bytes, blob.length, NULL, &body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_VALUE_OUT_OF_RANGE, result, ble_result_name(result));
}

static void test_weather_basel_clear_roundtrip(void)
{
    assert_weather_fixture_roundtrips("weather_basel_clear");
}

static void test_weather_alps_snow_roundtrip(void)
{
    assert_weather_fixture_roundtrips("weather_alps_snow");
}

static void test_weather_paris_rain_roundtrip(void)
{
    assert_weather_fixture_roundtrips("weather_paris_rain");
}

static void test_weather_cold_fog_roundtrip(void)
{
    assert_weather_fixture_roundtrips("weather_cold_fog");
}

static void test_weather_thunderstorm_roundtrip(void)
{
    assert_weather_fixture_roundtrips("weather_thunderstorm");
}

static void test_weather_over_max_temp_fixture_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("invalid", "weather_over_max_temp", &blob));
    ble_weather_data_t body;
    const ble_result_t result = ble_decode_weather(blob.bytes, blob.length, NULL, &body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_VALUE_OUT_OF_RANGE, result, ble_result_name(result));
}

static void test_music_playing_roundtrip(void)
{
    assert_music_fixture_roundtrips("music_playing");
}

static void test_music_paused_roundtrip(void)
{
    assert_music_fixture_roundtrips("music_paused");
}

static void test_music_long_titles_roundtrip(void)
{
    assert_music_fixture_roundtrips("music_long_titles");
}

static void test_music_unknown_duration_roundtrip(void)
{
    assert_music_fixture_roundtrips("music_unknown_duration");
}

static void test_music_title_too_long_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("invalid", "music_title_too_long", &blob));
    ble_music_data_t body;
    const ble_result_t result = ble_decode_music(blob.bytes, blob.length, NULL, &body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_UNTERMINATED_STRING, result, ble_result_name(result));
}

static void test_compass_out_of_range_fixture_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("invalid", "compass_out_of_range", &blob));
    ble_compass_data_t body;
    const ble_result_t result = ble_decode_compass(blob.bytes, blob.length, NULL, &body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_VALUE_OUT_OF_RANGE, result, ble_result_name(result));
}

static void assert_lean_angle_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_lean_angle_data_t decoded_body;
    const ble_result_t decoded =
        ble_decode_lean_angle(blob.bytes, blob.length, &flags, &decoded_body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded =
        ble_encode_lean_angle(&decoded_body, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void test_lean_upright_roundtrip(void)
{
    assert_lean_angle_fixture_roundtrips("lean_upright");
}

static void test_lean_moderate_right_roundtrip(void)
{
    assert_lean_angle_fixture_roundtrips("lean_moderate_right");
}

static void test_lean_hard_left_roundtrip(void)
{
    assert_lean_angle_fixture_roundtrips("lean_hard_left");
}

static void test_lean_racetrack_roundtrip(void)
{
    assert_lean_angle_fixture_roundtrips("lean_racetrack");
}

static void test_lean_over_max_fixture_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("invalid", "lean_over_max", &blob));
    ble_lean_angle_data_t body;
    const ble_result_t result = ble_decode_lean_angle(blob.bytes, blob.length, NULL, &body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_VALUE_OUT_OF_RANGE, result, ble_result_name(result));
}

static void assert_appointment_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_appointment_data_t decoded_body;
    const ble_result_t decoded =
        ble_decode_appointment(blob.bytes, blob.length, &flags, &decoded_body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded =
        ble_encode_appointment(&decoded_body, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void test_appointment_soon_roundtrip(void)
{
    assert_appointment_fixture_roundtrips("appointment_soon");
}

static void test_appointment_now_roundtrip(void)
{
    assert_appointment_fixture_roundtrips("appointment_now");
}

static void test_appointment_past_roundtrip(void)
{
    assert_appointment_fixture_roundtrips("appointment_past");
}

static void test_appointment_title_too_long_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("invalid", "appointment_title_too_long", &blob));
    ble_appointment_data_t body;
    const ble_result_t result = ble_decode_appointment(blob.bytes, blob.length, NULL, &body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_UNTERMINATED_STRING, result, ble_result_name(result));
}

/* ------------------------------------------------------------------------- */
/*                  invalid fixtures — each case fails cleanly               */
/* ------------------------------------------------------------------------- */

typedef struct {
    const char *name;
    ble_result_t expected;
} invalid_case_t;

/*
 * The expected errors mirror the JSON files under protocol/fixtures/invalid/.
 * Keep them in sync with the Swift InvalidFixtureTests mapping.
 */
static const invalid_case_t INVALID_CASES[] = {
    { "truncated_header", BLE_ERR_TRUNCATED_HEADER },
    { "unsupported_version", BLE_ERR_UNSUPPORTED_VERSION },
    { "nonzero_reserved", BLE_ERR_INVALID_RESERVED },
    { "unknown_screen_id", BLE_ERR_UNKNOWN_SCREEN_ID },
    { "body_length_mismatch", BLE_ERR_BODY_LENGTH_MISMATCH },
    { "truncated_body", BLE_ERR_TRUNCATED_BODY },
    { "reserved_flags_set", BLE_ERR_RESERVED_FLAGS_SET },
};

/*
 * speed_heading_out_of_range carries a valid header but an out-of-range
 * speed value; ble_decode_header can't catch that, so we dispatch through
 * the speed-heading decoder to exercise the VALUE_OUT_OF_RANGE path.
 */
static void test_speed_heading_out_of_range_fixture_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("invalid", "speed_heading_out_of_range", &blob));
    ble_speed_heading_data_t body;
    const ble_result_t result = ble_decode_speed_heading(blob.bytes, blob.length, NULL, &body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_VALUE_OUT_OF_RANGE, result, ble_result_name(result));
}

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
                 INVALID_CASES[i].name, ble_result_name(decoded),
                 ble_result_name(INVALID_CASES[i].expected));
        TEST_ASSERT_EQUAL_MESSAGE(INVALID_CASES[i].expected, decoded, message);
    }
}

/* ------------------------------------------------------------------------- */
/*                          control characteristic                            */
/* ------------------------------------------------------------------------- */

static void assert_control_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    char subdir[64];
    snprintf(subdir, sizeof(subdir), "control/valid");
    TEST_ASSERT_TRUE_MESSAGE(load_fixture(subdir, name, &blob), name);
    TEST_ASSERT_EQUAL_size_t(BLE_CONTROL_PAYLOAD_SIZE, blob.length);

    ble_control_payload_t payload;
    const ble_result_t decoded = ble_decode_control(blob.bytes, blob.length, &payload);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[BLE_CONTROL_PAYLOAD_SIZE] = { 0 };
    size_t written = 0;
    const ble_result_t encoded = ble_encode_control(&payload, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void test_control_set_active_clock(void)
{
    assert_control_fixture_roundtrips("set_active_clock");
}

static void test_control_set_active_nav(void)
{
    assert_control_fixture_roundtrips("set_active_nav");
}

static void test_control_set_brightness_50(void)
{
    assert_control_fixture_roundtrips("set_brightness_50");
}

static void test_control_set_brightness_100(void)
{
    assert_control_fixture_roundtrips("set_brightness_100");
}

static void test_control_sleep(void)
{
    assert_control_fixture_roundtrips("sleep");
}

static void test_control_wake(void)
{
    assert_control_fixture_roundtrips("wake");
}

static void test_control_clear_alert(void)
{
    assert_control_fixture_roundtrips("clear_alert");
}

static void test_control_unknown_command_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("control/invalid", "unknown_command", &blob));
    ble_control_payload_t payload;
    const ble_result_t result = ble_decode_control(blob.bytes, blob.length, &payload);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_UNKNOWN_COMMAND, result, ble_result_name(result));
}

static void test_control_brightness_over_100_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("control/invalid", "brightness_over_100", &blob));
    ble_control_payload_t payload;
    const ble_result_t result = ble_decode_control(blob.bytes, blob.length, &payload);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_INVALID_COMMAND_VALUE, result, ble_result_name(result));
}

static void test_control_truncated_rejected(void)
{
    const uint8_t bytes[3] = { 0x01, 0x01, 0x0D };
    ble_control_payload_t p;
    const ble_result_t result = ble_decode_control(bytes, sizeof(bytes), &p);
    TEST_ASSERT_EQUAL(BLE_ERR_TRUNCATED_HEADER, result);
}

static void test_control_unsupported_version_rejected(void)
{
    const uint8_t bytes[4] = { 0x02, 0x01, 0x0D, 0x00 };
    ble_control_payload_t p;
    const ble_result_t result = ble_decode_control(bytes, sizeof(bytes), &p);
    TEST_ASSERT_EQUAL(BLE_ERR_UNSUPPORTED_VERSION, result);
}

static void test_control_sleep_with_nonzero_value_rejected(void)
{
    const uint8_t bytes[4] = { 0x01, 0x03, 0x05, 0x00 };
    ble_control_payload_t p;
    const ble_result_t result = ble_decode_control(bytes, sizeof(bytes), &p);
    TEST_ASSERT_EQUAL(BLE_ERR_INVALID_RESERVED, result);
}

static void test_control_set_active_unknown_screen_rejected(void)
{
    const uint8_t bytes[4] = { 0x01, 0x01, 0xEE, 0x00 };
    ble_control_payload_t p;
    const ble_result_t result = ble_decode_control(bytes, sizeof(bytes), &p);
    TEST_ASSERT_EQUAL(BLE_ERR_UNKNOWN_SCREEN_ID, result);
}

/* ---- fuel (Slice 12) ---------------------------------------------------- */

static void assert_fuel_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_fuel_data_t decoded_body;
    const ble_result_t decoded = ble_decode_fuel(blob.bytes, blob.length, &flags, &decoded_body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded = ble_encode_fuel(&decoded_body, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void test_fuel_full_tank_roundtrip(void)
{
    assert_fuel_fixture_roundtrips("fuel_full_tank");
}

static void test_fuel_half_tank_roundtrip(void)
{
    assert_fuel_fixture_roundtrips("fuel_half_tank");
}

static void test_fuel_low_roundtrip(void)
{
    assert_fuel_fixture_roundtrips("fuel_low");
}

static void test_fuel_percent_over_100_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("invalid", "fuel_percent_over_100", &blob));
    ble_fuel_data_t body;
    const ble_result_t result = ble_decode_fuel(blob.bytes, blob.length, NULL, &body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_VALUE_OUT_OF_RANGE, result, ble_result_name(result));
}

/* ---- altitude (Slice 15) ------------------------------------------------ */

static void assert_altitude_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_altitude_profile_data_t decoded_body;
    const ble_result_t decoded =
        ble_decode_altitude(blob.bytes, blob.length, &flags, &decoded_body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded =
        ble_encode_altitude(&decoded_body, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void test_altitude_flat_roundtrip(void)
{
    assert_altitude_fixture_roundtrips("altitude_flat");
}

static void test_altitude_mountain_pass_roundtrip(void)
{
    assert_altitude_fixture_roundtrips("altitude_mountain_pass");
}

static void test_altitude_start_roundtrip(void)
{
    assert_altitude_fixture_roundtrips("altitude_start");
}

static void test_altitude_too_many_samples_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("invalid", "altitude_too_many_samples", &blob));
    ble_altitude_profile_data_t body;
    const ble_result_t result = ble_decode_altitude(blob.bytes, blob.length, NULL, &body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_VALUE_OUT_OF_RANGE, result, ble_result_name(result));
}

/* ---- incoming call (Slice 13) ------------------------------------------ */

static void assert_incoming_call_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_incoming_call_data_t decoded_body;
    const ble_result_t decoded =
        ble_decode_incoming_call(blob.bytes, blob.length, &flags, &decoded_body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded =
        ble_encode_incoming_call(&decoded_body, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void test_call_incoming_roundtrip(void)
{
    assert_incoming_call_fixture_roundtrips("call_incoming");
}

static void test_call_connected_roundtrip(void)
{
    assert_incoming_call_fixture_roundtrips("call_connected");
}

static void test_call_ended_roundtrip(void)
{
    assert_incoming_call_fixture_roundtrips("call_ended");
}

static void test_call_incoming_has_alert_flag(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("valid", "call_incoming", &blob));
    uint8_t flags = 0;
    ble_incoming_call_data_t call;
    const ble_result_t result = ble_decode_incoming_call(blob.bytes, blob.length, &flags, &call);
    TEST_ASSERT_EQUAL(BLE_OK, result);
    TEST_ASSERT_BITS_HIGH(BLE_FLAG_ALERT, flags);
}

static void test_call_ended_no_alert_flag(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("valid", "call_ended", &blob));
    uint8_t flags = 0xFF;
    ble_incoming_call_data_t call;
    const ble_result_t result = ble_decode_incoming_call(blob.bytes, blob.length, &flags, &call);
    TEST_ASSERT_EQUAL(BLE_OK, result);
    TEST_ASSERT_BITS_LOW(BLE_FLAG_ALERT, flags);
}

static void test_call_unknown_state_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("invalid", "call_unknown_state", &blob));
    ble_incoming_call_data_t call;
    const ble_result_t result = ble_decode_incoming_call(blob.bytes, blob.length, NULL, &call);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_VALUE_OUT_OF_RANGE, result, ble_result_name(result));
}

/* ---- blitzer (Slice 14) ------------------------------------------------ */

static void assert_blitzer_fixture_roundtrips(const char *name)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE_MESSAGE(load_fixture("valid", name, &blob), name);

    uint8_t flags = 0xFF;
    ble_blitzer_data_t decoded_body;
    const ble_result_t decoded = ble_decode_blitzer(blob.bytes, blob.length, &flags, &decoded_body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, decoded, ble_result_name(decoded));

    uint8_t out[256] = { 0 };
    size_t written = 0;
    const ble_result_t encoded =
        ble_encode_blitzer(&decoded_body, flags, out, sizeof(out), &written);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, encoded, ble_result_name(encoded));
    TEST_ASSERT_EQUAL_size_t(blob.length, written);
    TEST_ASSERT_EQUAL_MEMORY(blob.bytes, out, blob.length);
}

static void test_blitzer_fixed_500m_roundtrip(void)
{
    assert_blitzer_fixture_roundtrips("blitzer_fixed_500m");
}

static void test_blitzer_mobile_close_roundtrip(void)
{
    assert_blitzer_fixture_roundtrips("blitzer_mobile_close");
}

static void test_blitzer_section_roundtrip(void)
{
    assert_blitzer_fixture_roundtrips("blitzer_section");
}

static void test_blitzer_unknown_limit_roundtrip(void)
{
    assert_blitzer_fixture_roundtrips("blitzer_unknown_limit");
}

static void test_blitzer_fixed_500m_has_alert_flag(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("valid", "blitzer_fixed_500m", &blob));
    uint8_t flags = 0;
    ble_blitzer_data_t blitzer;
    const ble_result_t result = ble_decode_blitzer(blob.bytes, blob.length, &flags, &blitzer);
    TEST_ASSERT_EQUAL(BLE_OK, result);
    TEST_ASSERT_BITS_HIGH(BLE_FLAG_ALERT, flags);
}

static void test_blitzer_unknown_camera_type_rejected(void)
{
    fixture_blob_t blob;
    TEST_ASSERT_TRUE(load_fixture("invalid", "blitzer_unknown_camera_type", &blob));
    ble_blitzer_data_t body;
    const ble_result_t result = ble_decode_blitzer(blob.bytes, blob.length, NULL, &body);
    TEST_ASSERT_EQUAL_MESSAGE(BLE_ERR_VALUE_OUT_OF_RANGE, result, ble_result_name(result));
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
    RUN_TEST(test_speed_urban_45_roundtrip);
    RUN_TEST(test_speed_highway_120_roundtrip);
    RUN_TEST(test_speed_stationary_roundtrip);
    RUN_TEST(test_compass_north_magnetic_roundtrip);
    RUN_TEST(test_compass_east_true_roundtrip);
    RUN_TEST(test_compass_southwest_unknown_true_roundtrip);
    RUN_TEST(test_weather_basel_clear_roundtrip);
    RUN_TEST(test_weather_alps_snow_roundtrip);
    RUN_TEST(test_weather_paris_rain_roundtrip);
    RUN_TEST(test_weather_cold_fog_roundtrip);
    RUN_TEST(test_weather_thunderstorm_roundtrip);
    RUN_TEST(test_invalid_fixtures_are_rejected);
    RUN_TEST(test_speed_heading_out_of_range_fixture_rejected);
    RUN_TEST(test_compass_out_of_range_fixture_rejected);
    RUN_TEST(test_control_set_active_clock);
    RUN_TEST(test_control_set_active_nav);
    RUN_TEST(test_control_set_brightness_50);
    RUN_TEST(test_control_set_brightness_100);
    RUN_TEST(test_control_sleep);
    RUN_TEST(test_control_wake);
    RUN_TEST(test_control_clear_alert);
    RUN_TEST(test_control_unknown_command_rejected);
    RUN_TEST(test_control_brightness_over_100_rejected);
    RUN_TEST(test_control_truncated_rejected);
    RUN_TEST(test_control_unsupported_version_rejected);
    RUN_TEST(test_control_sleep_with_nonzero_value_rejected);
    RUN_TEST(test_control_set_active_unknown_screen_rejected);
    RUN_TEST(test_trip_stats_fresh_roundtrip);
    RUN_TEST(test_trip_stats_city_loop_roundtrip);
    RUN_TEST(test_trip_stats_highway_roundtrip);
    RUN_TEST(test_trip_stats_speed_out_of_range_fixture_rejected);
    RUN_TEST(test_weather_over_max_temp_fixture_rejected);
    RUN_TEST(test_lean_upright_roundtrip);
    RUN_TEST(test_lean_moderate_right_roundtrip);
    RUN_TEST(test_lean_hard_left_roundtrip);
    RUN_TEST(test_lean_racetrack_roundtrip);
    RUN_TEST(test_lean_over_max_fixture_rejected);
    RUN_TEST(test_music_playing_roundtrip);
    RUN_TEST(test_music_paused_roundtrip);
    RUN_TEST(test_music_long_titles_roundtrip);
    RUN_TEST(test_music_unknown_duration_roundtrip);
    RUN_TEST(test_music_title_too_long_rejected);
    RUN_TEST(test_appointment_soon_roundtrip);
    RUN_TEST(test_appointment_now_roundtrip);
    RUN_TEST(test_appointment_past_roundtrip);
    RUN_TEST(test_appointment_title_too_long_rejected);
    RUN_TEST(test_fuel_full_tank_roundtrip);
    RUN_TEST(test_fuel_half_tank_roundtrip);
    RUN_TEST(test_fuel_low_roundtrip);
    RUN_TEST(test_fuel_percent_over_100_rejected);
    RUN_TEST(test_altitude_flat_roundtrip);
    RUN_TEST(test_altitude_mountain_pass_roundtrip);
    RUN_TEST(test_altitude_start_roundtrip);
    RUN_TEST(test_altitude_too_many_samples_rejected);
    RUN_TEST(test_call_incoming_roundtrip);
    RUN_TEST(test_call_connected_roundtrip);
    RUN_TEST(test_call_ended_roundtrip);
    RUN_TEST(test_call_incoming_has_alert_flag);
    RUN_TEST(test_call_ended_no_alert_flag);
    RUN_TEST(test_call_unknown_state_rejected);
    RUN_TEST(test_blitzer_fixed_500m_roundtrip);
    RUN_TEST(test_blitzer_mobile_close_roundtrip);
    RUN_TEST(test_blitzer_section_roundtrip);
    RUN_TEST(test_blitzer_unknown_limit_roundtrip);
    RUN_TEST(test_blitzer_fixed_500m_has_alert_flag);
    RUN_TEST(test_blitzer_unknown_camera_type_rejected);
    return UNITY_END();
}
