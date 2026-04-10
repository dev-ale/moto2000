/*
 * test_blitzer_layout.c — Unity tests for the blitzer layout helper functions.
 */
#include "blitzer_layout.h"
#include "unity.h"

#include <string.h>

void setUp(void) {}
void tearDown(void) {}

/* ---- format_blitzer_distance ---- */

static void test_distance_meters_small(void)
{
    char buf[16];
    format_blitzer_distance(500, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("500M", buf);
}

static void test_distance_meters_zero(void)
{
    char buf[16];
    format_blitzer_distance(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("0M", buf);
}

static void test_distance_meters_999(void)
{
    char buf[16];
    format_blitzer_distance(999, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("999M", buf);
}

static void test_distance_km_exact(void)
{
    char buf[16];
    format_blitzer_distance(1000, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1.0KM", buf);
}

static void test_distance_km_fractional(void)
{
    char buf[16];
    format_blitzer_distance(1500, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1.5KM", buf);
}

static void test_distance_km_large(void)
{
    char buf[16];
    format_blitzer_distance(5200, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("5.2KM", buf);
}

/* ---- format_speed_limit ---- */

static void test_speed_limit_known(void)
{
    char buf[16];
    format_speed_limit(80, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("LIMIT 80", buf);
}

static void test_speed_limit_unknown(void)
{
    char buf[16];
    format_speed_limit(0xFFFF, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("LIMIT --", buf);
}

static void test_speed_limit_zero(void)
{
    char buf[16];
    format_speed_limit(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("LIMIT 0", buf);
}

/* ---- format_camera_type ---- */

static void test_camera_type_fixed(void)
{
    char buf[16];
    format_camera_type(0x00, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("FIXED", buf);
}

static void test_camera_type_mobile(void)
{
    char buf[16];
    format_camera_type(0x01, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("MOBILE", buf);
}

static void test_camera_type_red_light(void)
{
    char buf[16];
    format_camera_type(0x02, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("RED LIGHT", buf);
}

static void test_camera_type_section(void)
{
    char buf[16];
    format_camera_type(0x03, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("SECTION", buf);
}

static void test_camera_type_unknown(void)
{
    char buf[16];
    format_camera_type(0x04, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("UNKNOWN", buf);
}

static void test_camera_type_invalid(void)
{
    char buf[16];
    format_camera_type(0xFF, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("UNKNOWN", buf);
}

/* ---- is_speeding ---- */

static void test_is_speeding_over_limit(void)
{
    /* 85.0 km/h vs 80 limit */
    TEST_ASSERT_TRUE(is_speeding(850, 80));
}

static void test_is_speeding_at_limit(void)
{
    /* 80.0 km/h vs 80 limit — not speeding */
    TEST_ASSERT_FALSE(is_speeding(800, 80));
}

static void test_is_speeding_under_limit(void)
{
    /* 72.0 km/h vs 80 limit — not speeding */
    TEST_ASSERT_FALSE(is_speeding(720, 80));
}

static void test_is_speeding_unknown_limit(void)
{
    /* Unknown limit — never speeding */
    TEST_ASSERT_FALSE(is_speeding(1200, 0xFFFF));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_distance_meters_small);
    RUN_TEST(test_distance_meters_zero);
    RUN_TEST(test_distance_meters_999);
    RUN_TEST(test_distance_km_exact);
    RUN_TEST(test_distance_km_fractional);
    RUN_TEST(test_distance_km_large);
    RUN_TEST(test_speed_limit_known);
    RUN_TEST(test_speed_limit_unknown);
    RUN_TEST(test_speed_limit_zero);
    RUN_TEST(test_camera_type_fixed);
    RUN_TEST(test_camera_type_mobile);
    RUN_TEST(test_camera_type_red_light);
    RUN_TEST(test_camera_type_section);
    RUN_TEST(test_camera_type_unknown);
    RUN_TEST(test_camera_type_invalid);
    RUN_TEST(test_is_speeding_over_limit);
    RUN_TEST(test_is_speeding_at_limit);
    RUN_TEST(test_is_speeding_under_limit);
    RUN_TEST(test_is_speeding_unknown_limit);
    return UNITY_END();
}
