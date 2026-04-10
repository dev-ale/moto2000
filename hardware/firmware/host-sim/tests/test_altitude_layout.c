/*
 * Unit tests for the pure helpers in altitude_layout.c.
 *
 * Tests the coordinate-mapping and formatting functions only,
 * not the Bresenham line drawing (which is exercised by snapshot tests).
 */
#include "unity.h"
#include "altitude_layout.h"

#include <string.h>

void setUp(void) {}
void tearDown(void) {}

/* ---- altitude_graph_y --------------------------------------------------- */

static void test_graph_y_minAlt_mapsToBottom(void)
{
    const int y = altitude_graph_y(100, 100, 200, 50, 250);
    TEST_ASSERT_EQUAL_INT(250, y);
}

static void test_graph_y_maxAlt_mapsToTop(void)
{
    const int y = altitude_graph_y(200, 100, 200, 50, 250);
    TEST_ASSERT_EQUAL_INT(50, y);
}

static void test_graph_y_midAlt_mapsToCentre(void)
{
    const int y = altitude_graph_y(150, 100, 200, 50, 250);
    TEST_ASSERT_EQUAL_INT(150, y); /* exact midpoint */
}

static void test_graph_y_flatData_centresVertically(void)
{
    const int y = altitude_graph_y(260, 260, 260, 50, 250);
    TEST_ASSERT_EQUAL_INT(150, y); /* (50+250)/2 */
}

static void test_graph_y_clampsToTop(void)
{
    const int y = altitude_graph_y(300, 100, 200, 50, 250);
    TEST_ASSERT_EQUAL_INT(50, y);
}

static void test_graph_y_clampsToBottom(void)
{
    const int y = altitude_graph_y(0, 100, 200, 50, 250);
    TEST_ASSERT_EQUAL_INT(250, y);
}

/* ---- altitude_graph_x --------------------------------------------------- */

static void test_graph_x_firstSample_mapsToLeft(void)
{
    const int x = altitude_graph_x(0, 20, 80, 380);
    TEST_ASSERT_EQUAL_INT(80, x);
}

static void test_graph_x_lastSample_mapsToRight(void)
{
    const int x = altitude_graph_x(19, 20, 80, 380);
    TEST_ASSERT_EQUAL_INT(380, x);
}

static void test_graph_x_singleSample_centresHorizontally(void)
{
    const int x = altitude_graph_x(0, 1, 80, 380);
    TEST_ASSERT_EQUAL_INT(230, x); /* (80+380)/2 */
}

/* ---- format_altitude_label ---------------------------------------------- */

static void test_format_altitude_positive(void)
{
    char buf[12] = { 0 };
    format_altitude_label(2400, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("2400M", buf);
}

static void test_format_altitude_negative(void)
{
    char buf[12] = { 0 };
    format_altitude_label(-50, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("-50M", buf);
}

static void test_format_altitude_zero(void)
{
    char buf[12] = { 0 };
    format_altitude_label(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("0M", buf);
}

/* ---- format_altitude_delta ---------------------------------------------- */

static void test_format_delta_ascent(void)
{
    char buf[12] = { 0 };
    format_altitude_delta(1900, 1, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("+1900M", buf);
}

static void test_format_delta_descent(void)
{
    char buf[12] = { 0 };
    format_altitude_delta(600, 0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("-600M", buf);
}

static void test_format_delta_zero_ascent(void)
{
    char buf[12] = { 0 };
    format_altitude_delta(0, 1, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("+0M", buf);
}

/* ------------------------------------------------------------------------- */

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_graph_y_minAlt_mapsToBottom);
    RUN_TEST(test_graph_y_maxAlt_mapsToTop);
    RUN_TEST(test_graph_y_midAlt_mapsToCentre);
    RUN_TEST(test_graph_y_flatData_centresVertically);
    RUN_TEST(test_graph_y_clampsToTop);
    RUN_TEST(test_graph_y_clampsToBottom);
    RUN_TEST(test_graph_x_firstSample_mapsToLeft);
    RUN_TEST(test_graph_x_lastSample_mapsToRight);
    RUN_TEST(test_graph_x_singleSample_centresHorizontally);
    RUN_TEST(test_format_altitude_positive);
    RUN_TEST(test_format_altitude_negative);
    RUN_TEST(test_format_altitude_zero);
    RUN_TEST(test_format_delta_ascent);
    RUN_TEST(test_format_delta_descent);
    RUN_TEST(test_format_delta_zero_ascent);
    return UNITY_END();
}
