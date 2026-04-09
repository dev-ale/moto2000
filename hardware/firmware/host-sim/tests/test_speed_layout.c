/*
 * test_speed_layout.c — Unity tests for the pure-C layout helpers used
 * by the Speed + Heading renderer (screen_speed.c).
 */
#include "unity.h"

#include <string.h>

#include "host_sim/speed_layout.h"

void setUp(void)    {}
void tearDown(void) {}

/* ------------------------------- speed ------------------------------ */

static void test_speed_zero(void)
{
    char buf[8];
    const size_t n = host_sim_format_speed_kmh(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_UINT(3, n);
    TEST_ASSERT_EQUAL_STRING("  0", buf);
}

static void test_speed_single_digit_rounds(void)
{
    char buf[8];
    /* 4.7 km/h → 5 */
    (void)host_sim_format_speed_kmh(47, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("  5", buf);
}

static void test_speed_urban_45_3_kmh(void)
{
    char buf[8];
    /* 45.3 km/h → 45 */
    (void)host_sim_format_speed_kmh(453, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING(" 45", buf);
}

static void test_speed_highway_120(void)
{
    char buf[8];
    (void)host_sim_format_speed_kmh(1200, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("120", buf);
}

static void test_speed_clamps_above_999(void)
{
    char buf[8];
    (void)host_sim_format_speed_kmh(60000, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("999", buf);
}

static void test_speed_buffer_too_small(void)
{
    char buf[3];
    const size_t n = host_sim_format_speed_kmh(1200, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_UINT(0, n);
}

/* ----------------------------- altitude ----------------------------- */

static void test_altitude_positive(void)
{
    char buf[16];
    (void)host_sim_format_altitude_label(260, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("ALT 260M", buf);
}

static void test_altitude_negative_clamps_to_zero(void)
{
    char buf[16];
    (void)host_sim_format_altitude_label(-42, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("ALT 0M", buf);
}

static void test_altitude_max_int16_clamps(void)
{
    char buf[16];
    (void)host_sim_format_altitude_label((int16_t)32767, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("ALT 9999M", buf);
}

static void test_altitude_small_buffer(void)
{
    char buf[4];
    const size_t n = host_sim_format_altitude_label(100, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_UINT(0, n);
}

/* --------------------------- temperature ---------------------------- */

static void test_temperature_positive(void)
{
    char buf[16];
    (void)host_sim_format_temperature_label(140, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("T 14C", buf);
}

static void test_temperature_negative(void)
{
    char buf[16];
    (void)host_sim_format_temperature_label(-75, buf, sizeof(buf));
    /* -7.5 rounds away from zero → -8 */
    TEST_ASSERT_EQUAL_STRING("T -8C", buf);
}

static void test_temperature_clamps_high(void)
{
    char buf[16];
    (void)host_sim_format_temperature_label((int16_t)32000, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("T 199C", buf);
}

static void test_temperature_clamps_low(void)
{
    char buf[16];
    (void)host_sim_format_temperature_label((int16_t)-32000, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("T -99C", buf);
}

/* ------------------------------ heading ----------------------------- */

static void test_heading_label_north(void)
{
    char buf[16];
    (void)host_sim_format_heading_label(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("N 000", buf);
}

static void test_heading_label_east(void)
{
    char buf[16];
    (void)host_sim_format_heading_label(900, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("E 090", buf);
}

static void test_heading_label_urban_120(void)
{
    char buf[16];
    (void)host_sim_format_heading_label(1200, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("E 120", buf);
}

static void test_heading_label_south(void)
{
    char buf[16];
    (void)host_sim_format_heading_label(1800, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("S 180", buf);
}

static void test_heading_label_west(void)
{
    char buf[16];
    (void)host_sim_format_heading_label(2700, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("W 270", buf);
}

static void test_heading_label_near_north_wrap(void)
{
    char buf[16];
    (void)host_sim_format_heading_label(3500, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("N 350", buf);
}

/* ---------------------- heading arrow endpoint ---------------------- */

static void test_arrow_endpoint_north(void)
{
    int x = 0, y = 0;
    host_sim_heading_arrow_endpoint(0, 100, 100, 50, &x, &y);
    TEST_ASSERT_EQUAL_INT(100, x);
    TEST_ASSERT_EQUAL_INT(50, y);
}

static void test_arrow_endpoint_east(void)
{
    int x = 0, y = 0;
    host_sim_heading_arrow_endpoint(900, 100, 100, 50, &x, &y);
    TEST_ASSERT_EQUAL_INT(150, x);
    TEST_ASSERT_EQUAL_INT(100, y);
}

static void test_arrow_endpoint_south(void)
{
    int x = 0, y = 0;
    host_sim_heading_arrow_endpoint(1800, 100, 100, 50, &x, &y);
    TEST_ASSERT_EQUAL_INT(100, x);
    TEST_ASSERT_EQUAL_INT(150, y);
}

static void test_arrow_endpoint_west(void)
{
    int x = 0, y = 0;
    host_sim_heading_arrow_endpoint(2700, 100, 100, 50, &x, &y);
    TEST_ASSERT_EQUAL_INT(50, x);
    TEST_ASSERT_EQUAL_INT(100, y);
}

/* ------------------------ speed digit origin ------------------------ */

static void test_speed_digit_origin_centered(void)
{
    int x = 0, y = 0;
    host_sim_speed_digit_origin(466, 466, 3, 8, &x, &y);
    /* glyph_w = 64, total = 192, x = (466-192)/2 = 137 */
    TEST_ASSERT_EQUAL_INT(137, x);
    /* y = 466*36/100 - 32 = 167 - 32 = 135 */
    TEST_ASSERT_EQUAL_INT(135, y);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_speed_zero);
    RUN_TEST(test_speed_single_digit_rounds);
    RUN_TEST(test_speed_urban_45_3_kmh);
    RUN_TEST(test_speed_highway_120);
    RUN_TEST(test_speed_clamps_above_999);
    RUN_TEST(test_speed_buffer_too_small);
    RUN_TEST(test_altitude_positive);
    RUN_TEST(test_altitude_negative_clamps_to_zero);
    RUN_TEST(test_altitude_max_int16_clamps);
    RUN_TEST(test_altitude_small_buffer);
    RUN_TEST(test_temperature_positive);
    RUN_TEST(test_temperature_negative);
    RUN_TEST(test_temperature_clamps_high);
    RUN_TEST(test_temperature_clamps_low);
    RUN_TEST(test_heading_label_north);
    RUN_TEST(test_heading_label_east);
    RUN_TEST(test_heading_label_urban_120);
    RUN_TEST(test_heading_label_south);
    RUN_TEST(test_heading_label_west);
    RUN_TEST(test_heading_label_near_north_wrap);
    RUN_TEST(test_arrow_endpoint_north);
    RUN_TEST(test_arrow_endpoint_east);
    RUN_TEST(test_arrow_endpoint_south);
    RUN_TEST(test_arrow_endpoint_west);
    RUN_TEST(test_speed_digit_origin_centered);
    return UNITY_END();
}
