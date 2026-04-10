/*
 * test_appointment_layout.c — Unity host tests for appointment layout helpers.
 */
#include "unity.h"

#include "host_sim/appointment_layout.h"

#include <string.h>

void setUp(void) {}
void tearDown(void) {}

/* --------------------------------------------------------------------- */
/* format_starts_in                                                       */
/* --------------------------------------------------------------------- */

static void test_format_starts_in_positive(void)
{
    char buf[16] = { 0 };
    host_sim_appointment_format_starts_in(30, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("IN 30M", buf);
}

static void test_format_starts_in_now(void)
{
    char buf[16] = { 0 };
    host_sim_appointment_format_starts_in(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("NOW", buf);
}

static void test_format_starts_in_negative(void)
{
    char buf[16] = { 0 };
    host_sim_appointment_format_starts_in(-15, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("15M AGO", buf);
}

static void test_format_starts_in_large_positive(void)
{
    char buf[16] = { 0 };
    host_sim_appointment_format_starts_in(120, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("IN 120M", buf);
}

static void test_format_starts_in_large_negative(void)
{
    char buf[16] = { 0 };
    host_sim_appointment_format_starts_in(-1440, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1440M AGO", buf);
}

static void test_format_starts_in_one_minute(void)
{
    char buf[16] = { 0 };
    host_sim_appointment_format_starts_in(1, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("IN 1M", buf);
}

static void test_format_starts_in_minus_one(void)
{
    char buf[16] = { 0 };
    host_sim_appointment_format_starts_in(-1, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1M AGO", buf);
}

/* --------------------------------------------------------------------- */
/* uppercase_title                                                         */
/* --------------------------------------------------------------------- */

static void test_uppercase_title_short(void)
{
    char buf[32] = { 0 };
    host_sim_appointment_uppercase_title("Team standup", buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("TEAM STANDUP", buf);
}

static void test_uppercase_title_truncates_at_20(void)
{
    char buf[32] = { 0 };
    host_sim_appointment_uppercase_title("abcdefghijklmnopqrstuvwxyz", buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("ABCDEFGHIJKLMNOPQRST", buf);
    TEST_ASSERT_EQUAL_INT(20, (int)strlen(buf));
}

static void test_uppercase_title_empty(void)
{
    char buf[32] = { 0 };
    host_sim_appointment_uppercase_title("", buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("", buf);
}

static void test_uppercase_title_null_input(void)
{
    char buf[32] = { 'X' };
    host_sim_appointment_uppercase_title(NULL, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("", buf);
}

/* --------------------------------------------------------------------- */
/* uppercase_location                                                      */
/* --------------------------------------------------------------------- */

static void test_uppercase_location_short(void)
{
    char buf[32] = { 0 };
    host_sim_appointment_uppercase_location("Basel", buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("BASEL", buf);
}

static void test_uppercase_location_truncates_at_16(void)
{
    char buf[32] = { 0 };
    host_sim_appointment_uppercase_location("abcdefghijklmnopqrstuvwxyz", buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("ABCDEFGHIJKLMNOP", buf);
    TEST_ASSERT_EQUAL_INT(16, (int)strlen(buf));
}

static void test_uppercase_location_null(void)
{
    char buf[32] = { 'X' };
    host_sim_appointment_uppercase_location(NULL, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("", buf);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_format_starts_in_positive);
    RUN_TEST(test_format_starts_in_now);
    RUN_TEST(test_format_starts_in_negative);
    RUN_TEST(test_format_starts_in_large_positive);
    RUN_TEST(test_format_starts_in_large_negative);
    RUN_TEST(test_format_starts_in_one_minute);
    RUN_TEST(test_format_starts_in_minus_one);
    RUN_TEST(test_uppercase_title_short);
    RUN_TEST(test_uppercase_title_truncates_at_20);
    RUN_TEST(test_uppercase_title_empty);
    RUN_TEST(test_uppercase_title_null_input);
    RUN_TEST(test_uppercase_location_short);
    RUN_TEST(test_uppercase_location_truncates_at_16);
    RUN_TEST(test_uppercase_location_null);
    return UNITY_END();
}
