/*
 * test_time_format.c — Unity host tests for the pure-C clock/date
 * formatting helpers in host_sim/time_format.h.
 */
#include "unity.h"

#include <string.h>

#include "host_sim/time_format.h"

void setUp(void) {}
void tearDown(void) {}

static void test_format_24h_basel_winter(void)
{
    /* 2025-01-31 16:00:00 UTC + 60 minutes = 17:00 local. */
    char buf[16];
    const size_t n = host_sim_format_clock(1738339200LL, 60, true, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("17:00", buf);
    TEST_ASSERT_EQUAL_UINT(5, n);
}

static void test_format_12h_utc(void)
{
    /* 2025-01-31 16:00:00 UTC → 4:00 PM. */
    char buf[16];
    (void)host_sim_format_clock(1738339200LL, 0, false, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("4:00 PM", buf);
}

static void test_format_12h_midnight(void)
{
    /* Unix time 0 UTC = 1970-01-01 00:00:00 = "12:00 AM". */
    char buf[16];
    (void)host_sim_format_clock(0, 0, false, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("12:00 AM", buf);
}

static void test_format_12h_noon(void)
{
    char buf[16];
    (void)host_sim_format_clock(43200, 0, false, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("12:00 PM", buf);
}

static void test_format_24h_negative_tz(void)
{
    /* 2025-01-31 16:00:00 UTC − 300 min = 11:00 local. */
    char buf[16];
    (void)host_sim_format_clock(1738339200LL, -300, true, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("11:00", buf);
}

static void test_format_date_basel_winter(void)
{
    /* 2025-01-31 16:00 UTC + 60 = still 2025-01-31 local, Friday. */
    char buf[32];
    (void)host_sim_format_date(1738339200LL, 60, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("Fri 31 Jan", buf);
}

static void test_format_date_epoch(void)
{
    char buf[32];
    (void)host_sim_format_date(0, 0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("Thu 1 Jan", buf);
}

static void test_format_clock_buffer_too_small(void)
{
    char buf[4];
    const size_t n = host_sim_format_clock(0, 0, true, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_UINT(0, n);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_format_24h_basel_winter);
    RUN_TEST(test_format_12h_utc);
    RUN_TEST(test_format_12h_midnight);
    RUN_TEST(test_format_12h_noon);
    RUN_TEST(test_format_24h_negative_tz);
    RUN_TEST(test_format_date_basel_winter);
    RUN_TEST(test_format_date_epoch);
    RUN_TEST(test_format_clock_buffer_too_small);
    return UNITY_END();
}
