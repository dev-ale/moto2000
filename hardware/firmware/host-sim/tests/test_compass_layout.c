/*
 * test_compass_layout.c — Unity host tests for the compass math helpers.
 */
#include "unity.h"

#include "compass_layout.h"
#include "ble_protocol.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

void setUp(void) {}
void tearDown(void) {}

static int iabs(int v)
{
    return v < 0 ? -v : v;
}

static void assert_point_near(compass_point_t got, int ex, int ey, int tol, const char *tag)
{
    char msg[128];
    (void)snprintf(msg, sizeof(msg), "%s: expected (%d,%d) got (%d,%d)", tag, ex, ey, got.x, got.y);
    TEST_ASSERT_TRUE_MESSAGE(iabs(got.x - ex) <= tol, msg);
    TEST_ASSERT_TRUE_MESSAGE(iabs(got.y - ey) <= tol, msg);
}

/* -------------------------------------------------------------------- */
/* normalize                                                            */
/* -------------------------------------------------------------------- */

static void test_normalize_in_range_passthrough(void)
{
    TEST_ASSERT_EQUAL_UINT16(0U, host_sim_compass_normalize_deg_x10(0));
    TEST_ASSERT_EQUAL_UINT16(3599U, host_sim_compass_normalize_deg_x10(3599));
    TEST_ASSERT_EQUAL_UINT16(1800U, host_sim_compass_normalize_deg_x10(1800));
}

static void test_normalize_wraps_positive(void)
{
    TEST_ASSERT_EQUAL_UINT16(0U, host_sim_compass_normalize_deg_x10(3600));
    TEST_ASSERT_EQUAL_UINT16(10U, host_sim_compass_normalize_deg_x10(3610));
    TEST_ASSERT_EQUAL_UINT16(100U, host_sim_compass_normalize_deg_x10(7300));
}

static void test_normalize_wraps_negative(void)
{
    TEST_ASSERT_EQUAL_UINT16(3599U, host_sim_compass_normalize_deg_x10(-1));
    TEST_ASSERT_EQUAL_UINT16(3590U, host_sim_compass_normalize_deg_x10(-10));
    TEST_ASSERT_EQUAL_UINT16(2700U, host_sim_compass_normalize_deg_x10(-900));
}

/* -------------------------------------------------------------------- */
/* heading to whole degrees                                              */
/* -------------------------------------------------------------------- */

static void test_whole_deg_basic(void)
{
    TEST_ASSERT_EQUAL_UINT16(0U, host_sim_compass_heading_to_whole_deg(0));
    TEST_ASSERT_EQUAL_UINT16(42U, host_sim_compass_heading_to_whole_deg(420));
    TEST_ASSERT_EQUAL_UINT16(90U, host_sim_compass_heading_to_whole_deg(900));
    TEST_ASSERT_EQUAL_UINT16(225U, host_sim_compass_heading_to_whole_deg(2250));
    TEST_ASSERT_EQUAL_UINT16(359U, host_sim_compass_heading_to_whole_deg(3594));
}

static void test_whole_deg_rounds_half_up_and_wraps_360(void)
{
    /* 3595 -> rounds to 360, then wraps to 0 so the readout is never "360°". */
    TEST_ASSERT_EQUAL_UINT16(0U, host_sim_compass_heading_to_whole_deg(3595));
    /* 895 rounds to 90. */
    TEST_ASSERT_EQUAL_UINT16(90U, host_sim_compass_heading_to_whole_deg(895));
    /* 894 rounds down to 89. */
    TEST_ASSERT_EQUAL_UINT16(89U, host_sim_compass_heading_to_whole_deg(894));
}

/* -------------------------------------------------------------------- */
/* point on dial                                                         */
/* -------------------------------------------------------------------- */

static void test_point_on_dial_heading_north(void)
{
    /* Heading = 0° (north), so the cardinal labels sit at their
     * geographic positions around the dial. */
    const int cx = 100, cy = 100, r = 50;
    assert_point_near(host_sim_compass_point_on_dial(0, 0, cx, cy, r), 100, 50, 1, "N at 0");
    assert_point_near(host_sim_compass_point_on_dial(0, 900, cx, cy, r), 150, 100, 1, "E at 90");
    assert_point_near(host_sim_compass_point_on_dial(0, 1800, cx, cy, r), 100, 150, 1, "S at 180");
    assert_point_near(host_sim_compass_point_on_dial(0, 2700, cx, cy, r), 50, 100, 1, "W at 270");
}

static void test_point_on_dial_heading_east_rotates_dial(void)
{
    /* Heading = 90°: the dial rotates counter-clockwise so that East sits
     * at the top and North slides around to the left. */
    const int cx = 100, cy = 100, r = 50;
    assert_point_near(host_sim_compass_point_on_dial(900, 900, cx, cy, r), 100, 50, 1,
                      "E at top when heading east");
    assert_point_near(host_sim_compass_point_on_dial(900, 0, cx, cy, r), 50, 100, 1,
                      "N slides to the left");
    assert_point_near(host_sim_compass_point_on_dial(900, 1800, cx, cy, r), 150, 100, 1,
                      "S slides to the right");
}

static void test_point_on_dial_south_heading(void)
{
    const int cx = 200, cy = 200, r = 100;
    /* Heading = 180° (south): north is now at the bottom of the dial. */
    assert_point_near(host_sim_compass_point_on_dial(1800, 0, cx, cy, r), 200, 300, 2,
                      "N at the bottom");
    assert_point_near(host_sim_compass_point_on_dial(1800, 1800, cx, cy, r), 200, 100, 2,
                      "S at the top");
}

/* -------------------------------------------------------------------- */
/* displayed heading selection                                           */
/* -------------------------------------------------------------------- */

static void test_displayed_heading_prefers_magnetic_by_default(void)
{
    const uint16_t got = host_sim_compass_displayed_heading_x10(1200, 1250, 0);
    TEST_ASSERT_EQUAL_UINT16(1200, got);
}

static void test_displayed_heading_uses_true_when_flag_set(void)
{
    const uint16_t got =
        host_sim_compass_displayed_heading_x10(1200, 1250, BLE_COMPASS_FLAG_USE_TRUE_HEADING);
    TEST_ASSERT_EQUAL_UINT16(1250, got);
}

static void test_displayed_heading_falls_back_if_true_unknown(void)
{
    const uint16_t got = host_sim_compass_displayed_heading_x10(
        1200, BLE_COMPASS_TRUE_HEADING_UNKNOWN, BLE_COMPASS_FLAG_USE_TRUE_HEADING);
    TEST_ASSERT_EQUAL_UINT16(1200, got);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_normalize_in_range_passthrough);
    RUN_TEST(test_normalize_wraps_positive);
    RUN_TEST(test_normalize_wraps_negative);
    RUN_TEST(test_whole_deg_basic);
    RUN_TEST(test_whole_deg_rounds_half_up_and_wraps_360);
    RUN_TEST(test_point_on_dial_heading_north);
    RUN_TEST(test_point_on_dial_heading_east_rotates_dial);
    RUN_TEST(test_point_on_dial_south_heading);
    RUN_TEST(test_displayed_heading_prefers_magnetic_by_default);
    RUN_TEST(test_displayed_heading_uses_true_when_flag_set);
    RUN_TEST(test_displayed_heading_falls_back_if_true_unknown);
    return UNITY_END();
}
