/*
 * test_fuel_layout.c — Unity host tests for the fuel layout helpers.
 */
#include "unity.h"

#include "fuel_layout.h"

#include <stdint.h>
#include <string.h>

void setUp(void)    {}
void tearDown(void) {}

/* --------------------------------------------------------------------- */
/* format_tank_percent                                                     */
/* --------------------------------------------------------------------- */

static void test_format_tank_percent_full(void)
{
    char buf[8] = {0};
    format_tank_percent(100, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("100%", buf);
}

static void test_format_tank_percent_zero(void)
{
    char buf[8] = {0};
    format_tank_percent(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("0%", buf);
}

static void test_format_tank_percent_mid(void)
{
    char buf[8] = {0};
    format_tank_percent(73, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("73%", buf);
}

/* --------------------------------------------------------------------- */
/* format_range                                                            */
/* --------------------------------------------------------------------- */

static void test_format_range_known(void)
{
    char buf[16] = {0};
    format_range(175, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("175 KM", buf);
}

static void test_format_range_unknown(void)
{
    char buf[16] = {0};
    format_range(0xFFFF, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("-- KM", buf);
}

static void test_format_range_zero(void)
{
    char buf[16] = {0};
    format_range(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("0 KM", buf);
}

/* --------------------------------------------------------------------- */
/* format_consumption                                                      */
/* --------------------------------------------------------------------- */

static void test_format_consumption_known(void)
{
    char buf[16] = {0};
    format_consumption(38, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("38 ML/KM", buf);
}

static void test_format_consumption_unknown(void)
{
    char buf[16] = {0};
    format_consumption(0xFFFF, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("-- ML/KM", buf);
}

/* --------------------------------------------------------------------- */
/* format_fuel_remaining                                                   */
/* --------------------------------------------------------------------- */

static void test_format_fuel_remaining_full(void)
{
    char buf[16] = {0};
    format_fuel_remaining(13000, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("13.0 L", buf);
}

static void test_format_fuel_remaining_half(void)
{
    char buf[16] = {0};
    format_fuel_remaining(6500, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("6.5 L", buf);
}

static void test_format_fuel_remaining_unknown(void)
{
    char buf[16] = {0};
    format_fuel_remaining(0xFFFF, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("-- L", buf);
}

static void test_format_fuel_remaining_zero(void)
{
    char buf[16] = {0};
    format_fuel_remaining(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("0.0 L", buf);
}

static void test_format_fuel_remaining_small(void)
{
    char buf[16] = {0};
    format_fuel_remaining(1300, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1.3 L", buf);
}

/* --------------------------------------------------------------------- */
/* fuel_bar_fill                                                           */
/* --------------------------------------------------------------------- */

static void test_fuel_bar_fill_full(void)
{
    TEST_ASSERT_EQUAL_INT(200, fuel_bar_fill(100, 200));
}

static void test_fuel_bar_fill_empty(void)
{
    TEST_ASSERT_EQUAL_INT(0, fuel_bar_fill(0, 200));
}

static void test_fuel_bar_fill_half(void)
{
    TEST_ASSERT_EQUAL_INT(100, fuel_bar_fill(50, 200));
}

static void test_fuel_bar_fill_low(void)
{
    TEST_ASSERT_EQUAL_INT(20, fuel_bar_fill(10, 200));
}

static void test_fuel_bar_fill_clamps_over_100(void)
{
    /* If pct > 100, should clamp to bar_height */
    TEST_ASSERT_EQUAL_INT(200, fuel_bar_fill(150, 200));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_format_tank_percent_full);
    RUN_TEST(test_format_tank_percent_zero);
    RUN_TEST(test_format_tank_percent_mid);
    RUN_TEST(test_format_range_known);
    RUN_TEST(test_format_range_unknown);
    RUN_TEST(test_format_range_zero);
    RUN_TEST(test_format_consumption_known);
    RUN_TEST(test_format_consumption_unknown);
    RUN_TEST(test_format_fuel_remaining_full);
    RUN_TEST(test_format_fuel_remaining_half);
    RUN_TEST(test_format_fuel_remaining_unknown);
    RUN_TEST(test_format_fuel_remaining_zero);
    RUN_TEST(test_format_fuel_remaining_small);
    RUN_TEST(test_fuel_bar_fill_full);
    RUN_TEST(test_fuel_bar_fill_empty);
    RUN_TEST(test_fuel_bar_fill_half);
    RUN_TEST(test_fuel_bar_fill_low);
    RUN_TEST(test_fuel_bar_fill_clamps_over_100);
    return UNITY_END();
}
