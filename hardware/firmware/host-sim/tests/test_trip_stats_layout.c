/*
 * test_trip_stats_layout.c — Unity tests for the pure-C layout helpers
 * used by the Trip Stats renderer (screen_trip_stats.c).
 */
#include "unity.h"

#include <string.h>

#include "host_sim/trip_stats_layout.h"

void setUp(void) {}
void tearDown(void) {}

/* ----------------------------- distance ----------------------------- */

static void test_distance_zero(void)
{
    char buf[16];
    const size_t n = host_sim_format_distance(0U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_UINT(3, n);
    TEST_ASSERT_EQUAL_STRING("0 M", buf);
}

static void test_distance_below_one_km(void)
{
    char buf[16];
    (void)host_sim_format_distance(950U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("950 M", buf);
}

static void test_distance_just_under_one_km(void)
{
    char buf[16];
    (void)host_sim_format_distance(999U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("999 M", buf);
}

static void test_distance_one_km(void)
{
    char buf[16];
    (void)host_sim_format_distance(1000U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1.0 KM", buf);
}

static void test_distance_seven_point_four_km(void)
{
    char buf[16];
    (void)host_sim_format_distance(7400U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("7.4 KM", buf);
}

static void test_distance_round_up_to_decimal(void)
{
    char buf[16];
    /* 7449 m → 74.49 hundreds → rounds to 7.4 km */
    (void)host_sim_format_distance(7449U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("7.4 KM", buf);
    /* 7450 m → 74.5 hundreds → rounds to 7.5 km */
    (void)host_sim_format_distance(7450U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("7.5 KM", buf);
}

static void test_distance_127_km(void)
{
    char buf[16];
    (void)host_sim_format_distance(127000U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("127 KM", buf);
}

static void test_distance_max_uint32(void)
{
    char buf[16];
    const size_t n = host_sim_format_distance(UINT32_MAX, buf, sizeof(buf));
    TEST_ASSERT_TRUE(n > 0);
    /* Sanity: starts with a digit and ends with " KM". */
    TEST_ASSERT_TRUE(buf[0] >= '0' && buf[0] <= '9');
    TEST_ASSERT_NOT_NULL(strstr(buf, " KM"));
}

static void test_distance_buffer_too_small(void)
{
    char buf[4];
    const size_t n = host_sim_format_distance(7400U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_UINT(0, n);
}

/* ----------------------------- duration ----------------------------- */

static void test_duration_zero(void)
{
    char buf[16];
    (void)host_sim_format_duration(0U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("00:00", buf);
}

static void test_duration_under_one_minute(void)
{
    char buf[16];
    (void)host_sim_format_duration(7U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("00:07", buf);
}

static void test_duration_24_minutes_17(void)
{
    char buf[16];
    (void)host_sim_format_duration(24U * 60U + 17U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("24:17", buf);
}

static void test_duration_one_hour_24_17(void)
{
    char buf[16];
    /* 1*3600 + 24*60 + 17 = 5057 */
    (void)host_sim_format_duration(5057U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1:24:17", buf);
}

static void test_duration_clamps_above_99h(void)
{
    char buf[16];
    /* 100 h = 360000 s. Should clamp to 99:59:59. */
    (void)host_sim_format_duration(360000U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("99:59:59", buf);
}

/* ----------------------------- speed cell ---------------------------- */

static void test_speed_cell_avg_42(void)
{
    char buf[16];
    (void)host_sim_format_speed_cell("AVG", 420U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("AVG 42 KM/H", buf);
}

static void test_speed_cell_max_135(void)
{
    char buf[16];
    (void)host_sim_format_speed_cell("MAX", 1350U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("MAX 135 KM/H", buf);
}

static void test_speed_cell_rounds(void)
{
    char buf[16];
    /* 4.7 km/h rounds to 5 */
    (void)host_sim_format_speed_cell("AVG", 47U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("AVG 5 KM/H", buf);
}

/* ----------------------------- elevation ----------------------------- */

static void test_elevation_ascent(void)
{
    char buf[8];
    (void)host_sim_format_elevation_delta(120U, 0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("+120M", buf);
}

static void test_elevation_descent(void)
{
    char buf[8];
    (void)host_sim_format_elevation_delta(120U, 1, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("-120M", buf);
}

static void test_elevation_zero(void)
{
    char buf[8];
    (void)host_sim_format_elevation_delta(0U, 0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("+0M", buf);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_distance_zero);
    RUN_TEST(test_distance_below_one_km);
    RUN_TEST(test_distance_just_under_one_km);
    RUN_TEST(test_distance_one_km);
    RUN_TEST(test_distance_seven_point_four_km);
    RUN_TEST(test_distance_round_up_to_decimal);
    RUN_TEST(test_distance_127_km);
    RUN_TEST(test_distance_max_uint32);
    RUN_TEST(test_distance_buffer_too_small);
    RUN_TEST(test_duration_zero);
    RUN_TEST(test_duration_under_one_minute);
    RUN_TEST(test_duration_24_minutes_17);
    RUN_TEST(test_duration_one_hour_24_17);
    RUN_TEST(test_duration_clamps_above_99h);
    RUN_TEST(test_speed_cell_avg_42);
    RUN_TEST(test_speed_cell_max_135);
    RUN_TEST(test_speed_cell_rounds);
    RUN_TEST(test_elevation_ascent);
    RUN_TEST(test_elevation_descent);
    RUN_TEST(test_elevation_zero);
    return UNITY_END();
}
