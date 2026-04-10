/*
 * test_lean_angle_layout.c — Unity host tests for lean angle layout helpers.
 */
#include "unity.h"

#include "lean_angle_layout.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

void setUp(void) {}
void tearDown(void) {}

static int iabs(int v)
{
    return v < 0 ? -v : v;
}

/* -------------------------------------------------------------------- */
/* needle endpoint                                                      */
/* -------------------------------------------------------------------- */

static void test_needle_zero_lean_points_straight_up(void)
{
    int x = 0, y = 0;
    lean_arc_needle_endpoint(0, 100, 100, 50, &x, &y);
    /* Straight up: (cx, cy - radius). */
    TEST_ASSERT_EQUAL_INT(100, x);
    TEST_ASSERT_EQUAL_INT(50, y);
}

static void test_needle_positive_lean_points_right(void)
{
    int x = 0, y = 0;
    /* +30° right lean: x = cx + radius*sin(30°), y = cy - radius*cos(30°) */
    lean_arc_needle_endpoint(300, 100, 100, 50, &x, &y);
    TEST_ASSERT_TRUE_MESSAGE(iabs(x - (100 + 25)) <= 1, "x near 125");
    TEST_ASSERT_TRUE_MESSAGE(iabs(y - (100 - 43)) <= 1, "y near 57");
}

static void test_needle_negative_lean_points_left(void)
{
    int x = 0, y = 0;
    lean_arc_needle_endpoint(-300, 100, 100, 50, &x, &y);
    TEST_ASSERT_TRUE_MESSAGE(iabs(x - (100 - 25)) <= 1, "x near 75");
    TEST_ASSERT_TRUE_MESSAGE(iabs(y - (100 - 43)) <= 1, "y near 57");
}

static void test_needle_clamped_to_visual_max(void)
{
    /* Lean of 90° should clip back to 60° on the gauge. */
    int extreme_x = 0, extreme_y = 0;
    int sixty_x = 0, sixty_y = 0;
    lean_arc_needle_endpoint(900, 100, 100, 50, &extreme_x, &extreme_y);
    lean_arc_needle_endpoint(600, 100, 100, 50, &sixty_x, &sixty_y);
    TEST_ASSERT_EQUAL_INT(sixty_x, extreme_x);
    TEST_ASSERT_EQUAL_INT(sixty_y, extreme_y);
}

static void test_needle_clamped_negative(void)
{
    int extreme_x = 0, extreme_y = 0;
    int sixty_x = 0, sixty_y = 0;
    lean_arc_needle_endpoint(-900, 100, 100, 50, &extreme_x, &extreme_y);
    lean_arc_needle_endpoint(-600, 100, 100, 50, &sixty_x, &sixty_y);
    TEST_ASSERT_EQUAL_INT(sixty_x, extreme_x);
    TEST_ASSERT_EQUAL_INT(sixty_y, extreme_y);
}

/* -------------------------------------------------------------------- */
/* digital readout formatting                                            */
/* -------------------------------------------------------------------- */

static void test_format_lean_digital_zero(void)
{
    char buf[8];
    const size_t n = format_lean_digital(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_size_t(1, n);
    TEST_ASSERT_EQUAL_STRING("0", buf);
}

static void test_format_lean_digital_right(void)
{
    char buf[8];
    (void)format_lean_digital(250, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("R 25", buf);
}

static void test_format_lean_digital_left(void)
{
    char buf[8];
    (void)format_lean_digital(-425, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("L 43", buf); /* 42.5 rounds half-away-from-zero */
}

static void test_format_lean_digital_rounds_under_half(void)
{
    char buf[8];
    (void)format_lean_digital(244, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("R 24", buf);
}

static void test_format_lean_digital_max_positive(void)
{
    char buf[8];
    (void)format_lean_digital(900, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("R 90", buf);
}

static void test_format_lean_digital_max_negative(void)
{
    char buf[8];
    (void)format_lean_digital(-900, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("L 90", buf);
}

/* -------------------------------------------------------------------- */
/* max readout formatting                                                */
/* -------------------------------------------------------------------- */

static void test_format_max_lean_left(void)
{
    char buf[16];
    (void)format_max_lean(580, 'L', buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("MAX L 58", buf);
}

static void test_format_max_lean_right(void)
{
    char buf[16];
    (void)format_max_lean(620, 'R', buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("MAX R 62", buf);
}

static void test_format_max_lean_zero(void)
{
    char buf[16];
    (void)format_max_lean(0, 'L', buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("MAX L 0", buf);
}

static void test_format_max_lean_invalid_side_returns_zero(void)
{
    char buf[16] = { 0 };
    const size_t n = format_max_lean(580, 'X', buf, sizeof(buf));
    TEST_ASSERT_EQUAL_size_t(0, n);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_needle_zero_lean_points_straight_up);
    RUN_TEST(test_needle_positive_lean_points_right);
    RUN_TEST(test_needle_negative_lean_points_left);
    RUN_TEST(test_needle_clamped_to_visual_max);
    RUN_TEST(test_needle_clamped_negative);
    RUN_TEST(test_format_lean_digital_zero);
    RUN_TEST(test_format_lean_digital_right);
    RUN_TEST(test_format_lean_digital_left);
    RUN_TEST(test_format_lean_digital_rounds_under_half);
    RUN_TEST(test_format_lean_digital_max_positive);
    RUN_TEST(test_format_lean_digital_max_negative);
    RUN_TEST(test_format_max_lean_left);
    RUN_TEST(test_format_max_lean_right);
    RUN_TEST(test_format_max_lean_zero);
    RUN_TEST(test_format_max_lean_invalid_side_returns_zero);
    return UNITY_END();
}
