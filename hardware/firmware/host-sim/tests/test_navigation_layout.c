/*
 * test_navigation_layout.c — Unity host tests for the pure-C helpers
 * declared in host_sim/navigation_layout.h.
 */
#include "unity.h"

#include <string.h>

#include "host_sim/navigation_layout.h"
#include "ble_protocol.h"

void setUp(void) {}
void tearDown(void) {}

/* ------------------------------------------------------------------ */
/* Distance formatting                                                 */
/* ------------------------------------------------------------------ */

static void test_format_distance_metres_under_1000(void)
{
    char buf[16];
    const size_t n = host_sim_nav_format_distance(320U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("320M", buf);
    TEST_ASSERT_EQUAL_UINT(4, n);
}

static void test_format_distance_metres_zero(void)
{
    char buf[16];
    (void)host_sim_nav_format_distance(0U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("0M", buf);
}

static void test_format_distance_km_with_decimal(void)
{
    char buf[16];
    (void)host_sim_nav_format_distance(1200U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1.2KM", buf);
}

static void test_format_distance_km_rounds_to_hundreds(void)
{
    char buf[16];
    /* 500m → 0.5KM. */
    (void)host_sim_nav_format_distance(500U, buf, sizeof(buf));
    /* The boundary says "< 1000 is metres", so 500 stays "500M". */
    TEST_ASSERT_EQUAL_STRING("500M", buf);

    (void)host_sim_nav_format_distance(1000U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1.0KM", buf);
}

static void test_format_distance_unknown_sentinel(void)
{
    char buf[16];
    const size_t n = host_sim_nav_format_distance(0xFFFFU, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("--", buf);
    TEST_ASSERT_EQUAL_UINT(2, n);
}

static void test_format_distance_buffer_too_small(void)
{
    char buf[2];
    const size_t n = host_sim_nav_format_distance(320U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_UINT(0, n);
}

/* ------------------------------------------------------------------ */
/* ETA + remaining line                                                */
/* ------------------------------------------------------------------ */

static void test_format_eta_line_happy_path(void)
{
    char buf[64];
    (void)host_sim_nav_format_eta_line(18U, 74U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("ETA 18M  REM 7.4KM", buf);
}

static void test_format_eta_line_eta_unknown(void)
{
    char buf[64];
    (void)host_sim_nav_format_eta_line(0xFFFFU, 74U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("ETA --  REM 7.4KM", buf);
}

static void test_format_eta_line_remaining_unknown(void)
{
    char buf[64];
    (void)host_sim_nav_format_eta_line(10U, 0xFFFFU, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("ETA 10M  REM --", buf);
}

static void test_format_eta_line_large_remaining(void)
{
    char buf[64];
    /* 1234 → 123.4KM → prints "REM 123KM" (no decimal above 100KM). */
    (void)host_sim_nav_format_eta_line(200U, 1234U, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("ETA 200M  REM 123KM", buf);
}

/* ------------------------------------------------------------------ */
/* Arrow shape mapping                                                 */
/* ------------------------------------------------------------------ */

static void test_arrow_shape_mapping(void)
{
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_STRAIGHT, host_sim_nav_arrow_shape(BLE_MANEUVER_STRAIGHT));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_LEFT, host_sim_nav_arrow_shape(BLE_MANEUVER_LEFT));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_LEFT, host_sim_nav_arrow_shape(BLE_MANEUVER_SHARP_LEFT));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_LEFT, host_sim_nav_arrow_shape(BLE_MANEUVER_SLIGHT_LEFT));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_RIGHT, host_sim_nav_arrow_shape(BLE_MANEUVER_RIGHT));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_U_TURN_LEFT,
                          host_sim_nav_arrow_shape(BLE_MANEUVER_U_TURN_LEFT));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_U_TURN_RIGHT,
                          host_sim_nav_arrow_shape(BLE_MANEUVER_U_TURN_RIGHT));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_ROUNDABOUT,
                          host_sim_nav_arrow_shape(BLE_MANEUVER_ROUNDABOUT_ENTER));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_ROUNDABOUT,
                          host_sim_nav_arrow_shape(BLE_MANEUVER_ROUNDABOUT_EXIT));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_FORK_LEFT,
                          host_sim_nav_arrow_shape(BLE_MANEUVER_FORK_LEFT));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_FORK_RIGHT,
                          host_sim_nav_arrow_shape(BLE_MANEUVER_FORK_RIGHT));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_ARRIVE, host_sim_nav_arrow_shape(BLE_MANEUVER_ARRIVE));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_STRAIGHT, host_sim_nav_arrow_shape(BLE_MANEUVER_MERGE));
    TEST_ASSERT_EQUAL_INT(HOST_SIM_ARROW_STRAIGHT, host_sim_nav_arrow_shape(BLE_MANEUVER_NONE));
}

/* ------------------------------------------------------------------ */
/* Uppercase clamp                                                     */
/* ------------------------------------------------------------------ */

static void test_uppercase_clamp_lowercase_to_upper(void)
{
    char out[32];
    host_sim_nav_uppercase_clamp("Aeschengraben", out, sizeof(out));
    TEST_ASSERT_EQUAL_STRING("AESCHENGRABEN", out);
}

static void test_uppercase_clamp_truncates(void)
{
    char out[5];
    host_sim_nav_uppercase_clamp("aeschengraben", out, sizeof(out));
    TEST_ASSERT_EQUAL_STRING("AESC", out);
}

static void test_uppercase_clamp_null_input(void)
{
    char out[5];
    out[0] = 'X';
    host_sim_nav_uppercase_clamp(NULL, out, sizeof(out));
    TEST_ASSERT_EQUAL_STRING("", out);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_format_distance_metres_under_1000);
    RUN_TEST(test_format_distance_metres_zero);
    RUN_TEST(test_format_distance_km_with_decimal);
    RUN_TEST(test_format_distance_km_rounds_to_hundreds);
    RUN_TEST(test_format_distance_unknown_sentinel);
    RUN_TEST(test_format_distance_buffer_too_small);
    RUN_TEST(test_format_eta_line_happy_path);
    RUN_TEST(test_format_eta_line_eta_unknown);
    RUN_TEST(test_format_eta_line_remaining_unknown);
    RUN_TEST(test_format_eta_line_large_remaining);
    RUN_TEST(test_arrow_shape_mapping);
    RUN_TEST(test_uppercase_clamp_lowercase_to_upper);
    RUN_TEST(test_uppercase_clamp_truncates);
    RUN_TEST(test_uppercase_clamp_null_input);
    return UNITY_END();
}
