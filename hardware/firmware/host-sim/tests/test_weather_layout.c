/*
 * test_weather_layout.c — Unity host tests for the weather layout helpers.
 */
#include "unity.h"

#include "weather_layout.h"
#include "ble_protocol.h"

#include <stdint.h>
#include <string.h>

void setUp(void)    {}
void tearDown(void) {}

/* --------------------------------------------------------------------- */
/* format_temperature                                                      */
/* --------------------------------------------------------------------- */

static void test_format_temperature_positive(void)
{
    char buf[8] = {0};
    host_sim_weather_format_temperature(220, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("22", buf);
}

static void test_format_temperature_negative(void)
{
    char buf[8] = {0};
    host_sim_weather_format_temperature(-35, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("-3", buf);
}

static void test_format_temperature_zero(void)
{
    char buf[8] = {0};
    host_sim_weather_format_temperature(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("0", buf);
}

static void test_format_temperature_wire_max(void)
{
    char buf[8] = {0};
    host_sim_weather_format_temperature(600, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("60", buf);
}

static void test_format_temperature_wire_min(void)
{
    char buf[8] = {0};
    host_sim_weather_format_temperature(-500, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("-50", buf);
}

static void test_format_temperature_truncates_toward_zero(void)
{
    char buf[8] = {0};
    host_sim_weather_format_temperature(235, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("23", buf); /* 23.5 → 23, not 24 */
    host_sim_weather_format_temperature(-35, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("-3", buf); /* -3.5 → -3, not -4 */
}

/* --------------------------------------------------------------------- */
/* format_high_low                                                         */
/* --------------------------------------------------------------------- */

static void test_format_high_low_basic(void)
{
    char buf[16] = {0};
    host_sim_weather_format_high_low(250, 130, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("H 25  L 13", buf);
}

static void test_format_high_low_negative(void)
{
    char buf[16] = {0};
    host_sim_weather_format_high_low(-50, -150, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("H -5  L -15", buf);
}

/* --------------------------------------------------------------------- */
/* uppercase_location                                                      */
/* --------------------------------------------------------------------- */

static void test_uppercase_location_short(void)
{
    char buf[32] = {0};
    host_sim_weather_uppercase_location("Basel", buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("BASEL", buf);
}

static void test_uppercase_location_mixed(void)
{
    char buf[32] = {0};
    host_sim_weather_uppercase_location("St. Gotthard", buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("ST. GOTTHARD", buf);
}

static void test_uppercase_location_truncates_at_16(void)
{
    char buf[32] = {0};
    host_sim_weather_uppercase_location("abcdefghijklmnopqrstuvwxyz", buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("ABCDEFGHIJKLMNOP", buf);
    TEST_ASSERT_EQUAL_INT(16, (int)strlen(buf));
}

static void test_uppercase_location_empty(void)
{
    char buf[32] = {0};
    host_sim_weather_uppercase_location("", buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("", buf);
}

static void test_uppercase_location_null_input(void)
{
    char buf[32] = {'X'};
    host_sim_weather_uppercase_location(NULL, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("", buf);
}

/* --------------------------------------------------------------------- */
/* glyph_bounds                                                            */
/* --------------------------------------------------------------------- */

static void test_glyph_bounds_all_conditions(void)
{
    const ble_weather_condition_t conds[] = {
        BLE_WEATHER_CLEAR,
        BLE_WEATHER_CLOUDY,
        BLE_WEATHER_RAIN,
        BLE_WEATHER_SNOW,
        BLE_WEATHER_FOG,
        BLE_WEATHER_THUNDERSTORM,
    };
    for (size_t i = 0; i < sizeof(conds) / sizeof(conds[0]); ++i) {
        int w = 0;
        int h = 0;
        host_sim_weather_glyph_bounds(conds[i], &w, &h);
        TEST_ASSERT_EQUAL_INT(64, w);
        TEST_ASSERT_EQUAL_INT(48, h);
    }
}

static void test_glyph_bounds_unknown_condition(void)
{
    int w = -1;
    int h = -1;
    host_sim_weather_glyph_bounds((ble_weather_condition_t)0xFF, &w, &h);
    TEST_ASSERT_EQUAL_INT(0, w);
    TEST_ASSERT_EQUAL_INT(0, h);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_format_temperature_positive);
    RUN_TEST(test_format_temperature_negative);
    RUN_TEST(test_format_temperature_zero);
    RUN_TEST(test_format_temperature_wire_max);
    RUN_TEST(test_format_temperature_wire_min);
    RUN_TEST(test_format_temperature_truncates_toward_zero);
    RUN_TEST(test_format_high_low_basic);
    RUN_TEST(test_format_high_low_negative);
    RUN_TEST(test_uppercase_location_short);
    RUN_TEST(test_uppercase_location_mixed);
    RUN_TEST(test_uppercase_location_truncates_at_16);
    RUN_TEST(test_uppercase_location_empty);
    RUN_TEST(test_uppercase_location_null_input);
    RUN_TEST(test_glyph_bounds_all_conditions);
    RUN_TEST(test_glyph_bounds_unknown_condition);
    return UNITY_END();
}
