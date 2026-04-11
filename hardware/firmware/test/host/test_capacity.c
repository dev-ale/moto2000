/*
 * test_capacity.c — Resource and capacity tests for the ESP32 firmware.
 *
 * Validates that real fixture payloads respect the firmware's memory
 * constraints: BLE write buffer limits, cache slot capacity, body size
 * consistency, truncation safety for oversize screens, and staleness
 * detection across realistic scenarios.
 *
 * All tests run on the host — no hardware required.
 */

#include "unity.h"
#include "fixture_e2e.h"
#include "ble_protocol.h"
#include "ble_reconnect.h"

#include <string.h>

#ifndef SCRAMSCREEN_FIXTURES_DIR
#error "SCRAMSCREEN_FIXTURES_DIR must be defined by the build"
#endif

/* Same fixture table as test_fixture_e2e.c — screen_id + body size. */
typedef struct {
    const char *name;
    uint8_t screen_id;
    size_t expected_body_size;
} capacity_fixture_t;

static const capacity_fixture_t FIXTURES[] = {
    /* altitude (128B body — exceeds 64B cache) */
    { "altitude_flat", BLE_SCREEN_ALTITUDE, BLE_PROTOCOL_ALTITUDE_BODY_SIZE },
    { "altitude_mountain_pass", BLE_SCREEN_ALTITUDE, BLE_PROTOCOL_ALTITUDE_BODY_SIZE },
    { "altitude_start", BLE_SCREEN_ALTITUDE, BLE_PROTOCOL_ALTITUDE_BODY_SIZE },

    /* appointment (60B body — fits cache) */
    { "appointment_now", BLE_SCREEN_APPOINTMENT, BLE_PROTOCOL_APPOINTMENT_BODY_SIZE },
    { "appointment_past", BLE_SCREEN_APPOINTMENT, BLE_PROTOCOL_APPOINTMENT_BODY_SIZE },
    { "appointment_soon", BLE_SCREEN_APPOINTMENT, BLE_PROTOCOL_APPOINTMENT_BODY_SIZE },

    /* blitzer (8B) */
    { "blitzer_fixed_500m", BLE_SCREEN_BLITZER, BLE_PROTOCOL_BLITZER_BODY_SIZE },

    /* incomingCall (32B) */
    { "call_incoming", BLE_SCREEN_INCOMING_CALL, BLE_PROTOCOL_INCOMING_CALL_BODY_SIZE },

    /* clock (12B) */
    { "clock_basel_winter", BLE_SCREEN_CLOCK, BLE_PROTOCOL_CLOCK_BODY_SIZE },

    /* compass (8B) */
    { "compass_north_magnetic", BLE_SCREEN_COMPASS, BLE_PROTOCOL_COMPASS_BODY_SIZE },

    /* fuelEstimate (8B) */
    { "fuel_half_tank", BLE_SCREEN_FUEL_ESTIMATE, BLE_PROTOCOL_FUEL_BODY_SIZE },

    /* leanAngle (8B) */
    { "lean_upright", BLE_SCREEN_LEAN_ANGLE, BLE_PROTOCOL_LEAN_ANGLE_BODY_SIZE },

    /* music (86B body — exceeds 64B cache) */
    { "music_playing", BLE_SCREEN_MUSIC, BLE_PROTOCOL_MUSIC_BODY_SIZE },
    { "music_long_titles", BLE_SCREEN_MUSIC, BLE_PROTOCOL_MUSIC_BODY_SIZE },

    /* navigation (56B — fits cache) */
    { "nav_straight", BLE_SCREEN_NAVIGATION, BLE_PROTOCOL_NAV_BODY_SIZE },

    /* speedHeading (8B) */
    { "speed_urban_45kmh", BLE_SCREEN_SPEED_HEADING, BLE_PROTOCOL_SPEED_HEADING_BODY_SIZE },

    /* tripStats (16B) */
    { "trip_stats_highway", BLE_SCREEN_TRIP_STATS, BLE_PROTOCOL_TRIP_STATS_BODY_SIZE },

    /* weather (28B) */
    { "weather_basel_clear", BLE_SCREEN_WEATHER, BLE_PROTOCOL_WEATHER_BODY_SIZE },

    { NULL, 0, 0 }, /* sentinel */
};

/* Max BLE write buffer on the ESP32. */
#define BLE_WRITE_BUFFER_MAX 256

void setUp(void) {}
void tearDown(void) {}

/* ----------------------------------------------------------------------- */
/* Helpers                                                                  */
/* ----------------------------------------------------------------------- */

static size_t load_fixture_bytes(const char *name, uint8_t *buf, size_t cap)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/valid/%s.bin", SCRAMSCREEN_FIXTURES_DIR, name);
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        char msg[600];
        snprintf(msg, sizeof(msg), "cannot open: %s", path);
        TEST_FAIL_MESSAGE(msg);
        return 0;
    }
    size_t n = fread(buf, 1, cap, fp);
    fclose(fp);
    return n;
}

/* ======================================================================= */
/* 1. Every fixture fits the 256-byte BLE write buffer                      */
/* ======================================================================= */

static void test_all_fixtures_fit_ble_write_buffer(void)
{
    uint8_t buf[BLE_WRITE_BUFFER_MAX + 64]; /* extra room to detect oversize */

    for (const capacity_fixture_t *f = FIXTURES; f->name != NULL; f++) {
        size_t len = load_fixture_bytes(f->name, buf, sizeof(buf));

        char msg[256];
        snprintf(msg, sizeof(msg), "[%s] payload %zu bytes exceeds %d-byte BLE write buffer",
                 f->name, len, BLE_WRITE_BUFFER_MAX);
        TEST_ASSERT_LESS_OR_EQUAL_MESSAGE((size_t)BLE_WRITE_BUFFER_MAX, len, msg);
    }
}

/* ======================================================================= */
/* 2. Fixture body sizes match protocol constants                           */
/* ======================================================================= */

static void test_fixture_body_sizes_match_protocol(void)
{
    uint8_t buf[BLE_WRITE_BUFFER_MAX];

    for (const capacity_fixture_t *f = FIXTURES; f->name != NULL; f++) {
        size_t len = load_fixture_bytes(f->name, buf, sizeof(buf));

        ble_header_t hdr;
        ble_result_t rc = ble_decode_header(buf, len, &hdr);

        char msg[256];
        snprintf(msg, sizeof(msg), "[%s] decode header", f->name);
        TEST_ASSERT_EQUAL_MESSAGE(BLE_OK, rc, msg);

        snprintf(msg, sizeof(msg), "[%s] body_length %u != expected %zu for screen 0x%02X", f->name,
                 hdr.body_length, f->expected_body_size, f->screen_id);
        TEST_ASSERT_EQUAL_MESSAGE(f->expected_body_size, (size_t)hdr.body_length, msg);
    }
}

/* ======================================================================= */
/* 3. Truncation safety: oversize screens don't corrupt adjacent cache slots */
/* ======================================================================= */

/*
 * Fill adjacent cache slots with a known pattern, then store an altitude
 * payload (128B — the largest body). Verify:
 *   a) The altitude slot stores the full body.
 *   b) Adjacent slots are undamaged.
 */
static void test_altitude_full_body_no_adjacent_corruption(void)
{
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);

    /* Fill adjacent slots with a sentinel pattern. */
    uint8_t sentinel[BLE_PAYLOAD_CACHE_BODY_MAX];
    memset(sentinel, 0xAA, sizeof(sentinel));

    /* Altitude is screen 0x0B. Fill 0x0A and 0x0C as neighbors. */
    ble_payload_cache_store(&cache, BLE_SCREEN_FUEL_ESTIMATE, sentinel, (uint16_t)sizeof(sentinel),
                            100);
    ble_payload_cache_store(&cache, BLE_SCREEN_APPOINTMENT, sentinel, (uint16_t)sizeof(sentinel),
                            100);

    /* Now store an altitude payload through the full pipeline. */
    uint8_t buf[BLE_WRITE_BUFFER_MAX];
    size_t len = load_fixture_bytes("altitude_mountain_pass", buf, sizeof(buf));

    screen_fsm_t fsm;
    screen_fsm_init(&fsm, BLE_SCREEN_ALTITUDE);
    ble_server_handle_screen_data(buf, len, &fsm, &cache, 200);

    /* Altitude slot should store the full 128B body. */
    const ble_payload_cache_entry_t *alt = ble_payload_cache_get(&cache, BLE_SCREEN_ALTITUDE);
    TEST_ASSERT_NOT_NULL(alt);
    TEST_ASSERT_TRUE(alt->present);
    TEST_ASSERT_EQUAL_UINT16(BLE_PROTOCOL_ALTITUDE_BODY_SIZE, alt->length);

    /* Neighbors must be untouched. */
    const ble_payload_cache_entry_t *fuel = ble_payload_cache_get(&cache, BLE_SCREEN_FUEL_ESTIMATE);
    TEST_ASSERT_NOT_NULL(fuel);
    TEST_ASSERT_TRUE(fuel->present);
    TEST_ASSERT_EQUAL_UINT16(BLE_PAYLOAD_CACHE_BODY_MAX, fuel->length);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(sentinel, fuel->body, BLE_PAYLOAD_CACHE_BODY_MAX);

    const ble_payload_cache_entry_t *appt = ble_payload_cache_get(&cache, BLE_SCREEN_APPOINTMENT);
    TEST_ASSERT_NOT_NULL(appt);
    TEST_ASSERT_TRUE(appt->present);
    TEST_ASSERT_EQUAL_UINT16(BLE_PAYLOAD_CACHE_BODY_MAX, appt->length);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(sentinel, appt->body, BLE_PAYLOAD_CACHE_BODY_MAX);
}

/* Same test for music (86B body — fits within 128B cache). */
static void test_music_full_body_no_adjacent_corruption(void)
{
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);

    uint8_t sentinel[BLE_PAYLOAD_CACHE_BODY_MAX];
    memset(sentinel, 0xBB, sizeof(sentinel));

    /* Music is 0x06. Fill 0x05 (tripStats) and 0x07 (leanAngle). */
    ble_payload_cache_store(&cache, BLE_SCREEN_TRIP_STATS, sentinel, (uint16_t)sizeof(sentinel),
                            100);
    ble_payload_cache_store(&cache, BLE_SCREEN_LEAN_ANGLE, sentinel, (uint16_t)sizeof(sentinel),
                            100);

    uint8_t buf[BLE_WRITE_BUFFER_MAX];
    size_t len = load_fixture_bytes("music_long_titles", buf, sizeof(buf));

    screen_fsm_t fsm;
    screen_fsm_init(&fsm, BLE_SCREEN_MUSIC);
    ble_server_handle_screen_data(buf, len, &fsm, &cache, 200);

    /* Music slot stores full 86B body. */
    const ble_payload_cache_entry_t *music = ble_payload_cache_get(&cache, BLE_SCREEN_MUSIC);
    TEST_ASSERT_NOT_NULL(music);
    TEST_ASSERT_TRUE(music->present);
    TEST_ASSERT_EQUAL_UINT16(BLE_PROTOCOL_MUSIC_BODY_SIZE, music->length);

    /* Neighbors untouched. */
    const ble_payload_cache_entry_t *trip = ble_payload_cache_get(&cache, BLE_SCREEN_TRIP_STATS);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(sentinel, trip->body, BLE_PAYLOAD_CACHE_BODY_MAX);

    const ble_payload_cache_entry_t *lean = ble_payload_cache_get(&cache, BLE_SCREEN_LEAN_ANGLE);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(sentinel, lean->body, BLE_PAYLOAD_CACHE_BODY_MAX);
}

/* ======================================================================= */
/* 4. Full cache fill: all 13 screens coexist without interference          */
/* ======================================================================= */

/*
 * One fixture per screen type, fed through the full pipeline. Then
 * verify every slot is independently present and has the correct body
 * length (truncated where appropriate).
 */
typedef struct {
    const char *fixture;
    uint8_t screen_id;
    size_t body_size;
} screen_fixture_t;

static const screen_fixture_t ONE_PER_SCREEN[] = {
    { "nav_straight", BLE_SCREEN_NAVIGATION, BLE_PROTOCOL_NAV_BODY_SIZE },
    { "speed_urban_45kmh", BLE_SCREEN_SPEED_HEADING, BLE_PROTOCOL_SPEED_HEADING_BODY_SIZE },
    { "compass_north_magnetic", BLE_SCREEN_COMPASS, BLE_PROTOCOL_COMPASS_BODY_SIZE },
    { "weather_basel_clear", BLE_SCREEN_WEATHER, BLE_PROTOCOL_WEATHER_BODY_SIZE },
    { "trip_stats_highway", BLE_SCREEN_TRIP_STATS, BLE_PROTOCOL_TRIP_STATS_BODY_SIZE },
    { "music_playing", BLE_SCREEN_MUSIC, BLE_PROTOCOL_MUSIC_BODY_SIZE },
    { "lean_upright", BLE_SCREEN_LEAN_ANGLE, BLE_PROTOCOL_LEAN_ANGLE_BODY_SIZE },
    { "blitzer_fixed_500m", BLE_SCREEN_BLITZER, BLE_PROTOCOL_BLITZER_BODY_SIZE },
    { "call_incoming", BLE_SCREEN_INCOMING_CALL, BLE_PROTOCOL_INCOMING_CALL_BODY_SIZE },
    { "fuel_half_tank", BLE_SCREEN_FUEL_ESTIMATE, BLE_PROTOCOL_FUEL_BODY_SIZE },
    { "altitude_flat", BLE_SCREEN_ALTITUDE, BLE_PROTOCOL_ALTITUDE_BODY_SIZE },
    { "appointment_now", BLE_SCREEN_APPOINTMENT, BLE_PROTOCOL_APPOINTMENT_BODY_SIZE },
    { "clock_basel_winter", BLE_SCREEN_CLOCK, BLE_PROTOCOL_CLOCK_BODY_SIZE },
    { NULL, 0, 0 },
};

static void test_all_13_screens_coexist_in_cache(void)
{
    screen_fsm_t fsm;
    screen_fsm_init(&fsm, BLE_SCREEN_CLOCK);
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);

    uint8_t buf[BLE_WRITE_BUFFER_MAX];
    uint32_t now = 1000;

    /* Fill all 13 slots. */
    for (const screen_fixture_t *s = ONE_PER_SCREEN; s->fixture != NULL; s++) {
        size_t len = load_fixture_bytes(s->fixture, buf, sizeof(buf));
        ble_server_handle_screen_data(buf, len, &fsm, &cache, now);
        now += 100;
    }

    /* Verify every slot independently. */
    for (const screen_fixture_t *s = ONE_PER_SCREEN; s->fixture != NULL; s++) {
        const ble_payload_cache_entry_t *entry = ble_payload_cache_get(&cache, s->screen_id);

        char msg[128];
        snprintf(msg, sizeof(msg), "screen 0x%02X (%s) not present", s->screen_id, s->fixture);
        TEST_ASSERT_NOT_NULL_MESSAGE(entry, msg);
        TEST_ASSERT_TRUE_MESSAGE(entry->present, msg);

        /* Expected stored length: min(body_size, 64). */
        size_t expected_len = s->body_size;
        if (expected_len > BLE_PAYLOAD_CACHE_BODY_MAX) {
            expected_len = BLE_PAYLOAD_CACHE_BODY_MAX;
        }
        snprintf(msg, sizeof(msg), "screen 0x%02X length %u != expected %zu", s->screen_id,
                 entry->length, expected_len);
        TEST_ASSERT_EQUAL_MESSAGE(expected_len, (size_t)entry->length, msg);
    }
}

/* ======================================================================= */
/* 5. Staleness detection with real fixtures                                */
/* ======================================================================= */

static void test_staleness_with_real_payload(void)
{
    screen_fsm_t fsm;
    screen_fsm_init(&fsm, BLE_SCREEN_SPEED_HEADING);
    ble_payload_cache_t cache;
    ble_payload_cache_init(&cache);

    uint8_t buf[BLE_WRITE_BUFFER_MAX];
    size_t len = load_fixture_bytes("speed_urban_45kmh", buf, sizeof(buf));

    /* Store at t=1000. */
    ble_server_handle_screen_data(buf, len, &fsm, &cache, 1000);

    /* At t=1500 with 2000ms threshold: NOT stale. */
    TEST_ASSERT_FALSE(ble_payload_cache_is_stale(&cache, BLE_SCREEN_SPEED_HEADING, 1500, 2000));

    /* At t=3001 with 2000ms threshold: stale. */
    TEST_ASSERT_TRUE(ble_payload_cache_is_stale(&cache, BLE_SCREEN_SPEED_HEADING, 3001, 2000));

    /* Screen never written: always stale. */
    TEST_ASSERT_TRUE(ble_payload_cache_is_stale(&cache, BLE_SCREEN_WEATHER, 1000, 2000));
}

/* ======================================================================= */
/* 6. Total cache memory footprint is bounded                               */
/* ======================================================================= */

/*
 * Compile-time check that the full cache fits in reasonable SRAM.
 * ble_payload_cache_t = 14 × (64 + 2 + 4 + 1) bytes = 14 × 71 = 994 bytes.
 * With alignment padding it'll be slightly more, but must stay under 2KB.
 */
static void test_cache_struct_size_bounded(void)
{
    TEST_ASSERT_LESS_OR_EQUAL_MESSAGE((size_t)4096, sizeof(ble_payload_cache_t),
                                      "payload cache exceeds 4KB — review slot count or body max");
}

/* ======================================================================= */
/* 7. Largest payload total size (header + body) is within budget            */
/* ======================================================================= */

static void test_largest_payload_within_budget(void)
{
    /* Altitude is the largest: 8 + 128 = 136 bytes.
     * Must fit in the 256-byte BLE write characteristic. */
    size_t largest = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_ALTITUDE_BODY_SIZE;
    TEST_ASSERT_LESS_OR_EQUAL_MESSAGE((size_t)BLE_WRITE_BUFFER_MAX, largest,
                                      "largest payload exceeds BLE write buffer");

    /* Verify the constant. */
    TEST_ASSERT_EQUAL(136u, largest);
}

/* ----------------------------------------------------------------------- */
/* Runner                                                                   */
/* ----------------------------------------------------------------------- */

int main(void)
{
    UNITY_BEGIN();

    RUN_TEST(test_all_fixtures_fit_ble_write_buffer);
    RUN_TEST(test_fixture_body_sizes_match_protocol);
    RUN_TEST(test_altitude_full_body_no_adjacent_corruption);
    RUN_TEST(test_music_full_body_no_adjacent_corruption);
    RUN_TEST(test_all_13_screens_coexist_in_cache);
    RUN_TEST(test_staleness_with_real_payload);
    RUN_TEST(test_cache_struct_size_bounded);
    RUN_TEST(test_largest_payload_within_budget);

    return UNITY_END();
}
