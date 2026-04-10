/*
 * test_display_stub.c -- Host-side tests for the display driver header.
 *
 * LVGL is NOT available in the host-test harness, so we cannot compile or
 * link display_stub.c / display_common.c here.  Instead we verify:
 *
 *   1. display.h compiles cleanly under -Wall -Werror on the host.
 *   2. DISPLAY_WIDTH / DISPLAY_HEIGHT constants have the correct values.
 *
 * Full LVGL-integrated stub testing is deferred to the lvgl-sim project
 * which already has LVGL configured.
 */

#include "unity.h"
#include "display.h"  /* header under test */

/* ------------------------------------------------------------------ */
/* Tests                                                               */
/* ------------------------------------------------------------------ */

void test_display_width_is_466(void)
{
    TEST_ASSERT_EQUAL_INT(466, DISPLAY_WIDTH);
}

void test_display_height_is_466(void)
{
    TEST_ASSERT_EQUAL_INT(466, DISPLAY_HEIGHT);
}

void test_display_dimensions_are_square(void)
{
    TEST_ASSERT_EQUAL_INT(DISPLAY_WIDTH, DISPLAY_HEIGHT);
}

/* ------------------------------------------------------------------ */
/* Runner                                                              */
/* ------------------------------------------------------------------ */

void setUp(void) {}
void tearDown(void) {}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_display_width_is_466);
    RUN_TEST(test_display_height_is_466);
    RUN_TEST(test_display_dimensions_are_square);
    return UNITY_END();
}
