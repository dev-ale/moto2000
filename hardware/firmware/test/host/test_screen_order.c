/*
 * Host-side Unity tests for screen_order.
 */
#include "screen_order.h"
#include "unity.h"

#include <stdint.h>

#define NAV     ((uint8_t)0x01u)
#define SPEED   ((uint8_t)0x02u)
#define COMPASS ((uint8_t)0x03u)
#define WEATHER ((uint8_t)0x04u)
#define CLOCK   ((uint8_t)0x0Du)

void setUp(void) {}
void tearDown(void) {}

/* ----- init ------------------------------------------------------------- */

static void test_init_is_empty(void)
{
    screen_order_t order;
    screen_order_init(&order);
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_count(&order));
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_current(&order));
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_first(&order));
}

static void test_init_null_is_safe(void)
{
    screen_order_init(NULL); /* must not crash */
}

/* ----- set and cycle ---------------------------------------------------- */

static void test_set_order_and_cycle(void)
{
    screen_order_t order;
    screen_order_init(&order);

    const uint8_t ids[] = { NAV, COMPASS, CLOCK };
    TEST_ASSERT_TRUE(screen_order_set(&order, ids, 3));

    TEST_ASSERT_EQUAL_UINT8(3, screen_order_count(&order));
    TEST_ASSERT_EQUAL_UINT8(NAV, screen_order_current(&order));
    TEST_ASSERT_EQUAL_UINT8(NAV, screen_order_first(&order));

    TEST_ASSERT_EQUAL_UINT8(COMPASS, screen_order_next(&order));
    TEST_ASSERT_EQUAL_UINT8(COMPASS, screen_order_current(&order));

    TEST_ASSERT_EQUAL_UINT8(CLOCK, screen_order_next(&order));
    TEST_ASSERT_EQUAL_UINT8(CLOCK, screen_order_current(&order));
}

static void test_wrap_around(void)
{
    screen_order_t order;
    screen_order_init(&order);

    const uint8_t ids[] = { NAV, COMPASS, CLOCK };
    screen_order_set(&order, ids, 3);

    screen_order_next(&order);                               /* -> COMPASS */
    screen_order_next(&order);                               /* -> CLOCK */
    TEST_ASSERT_EQUAL_UINT8(NAV, screen_order_next(&order)); /* wrap */
}

static void test_prev_wraps_around(void)
{
    screen_order_t order;
    screen_order_init(&order);

    const uint8_t ids[] = { NAV, COMPASS, CLOCK };
    screen_order_set(&order, ids, 3);

    /* At index 0, prev should wrap to last. */
    TEST_ASSERT_EQUAL_UINT8(CLOCK, screen_order_prev(&order));
    TEST_ASSERT_EQUAL_UINT8(COMPASS, screen_order_prev(&order));
    TEST_ASSERT_EQUAL_UINT8(NAV, screen_order_prev(&order));
}

/* ----- empty order ------------------------------------------------------ */

static void test_empty_order_returns_zero(void)
{
    screen_order_t order;
    screen_order_init(&order);

    TEST_ASSERT_EQUAL_UINT8(0, screen_order_next(&order));
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_prev(&order));
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_current(&order));
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_first(&order));
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_handle_button_press(&order));
}

/* ----- single screen ---------------------------------------------------- */

static void test_single_screen_order(void)
{
    screen_order_t order;
    screen_order_init(&order);

    const uint8_t ids[] = { WEATHER };
    screen_order_set(&order, ids, 1);

    TEST_ASSERT_EQUAL_UINT8(1, screen_order_count(&order));
    TEST_ASSERT_EQUAL_UINT8(WEATHER, screen_order_current(&order));
    TEST_ASSERT_EQUAL_UINT8(WEATHER, screen_order_next(&order));
    TEST_ASSERT_EQUAL_UINT8(WEATHER, screen_order_prev(&order));
}

/* ----- button press ----------------------------------------------------- */

static void test_button_press_advances(void)
{
    screen_order_t order;
    screen_order_init(&order);

    const uint8_t ids[] = { NAV, SPEED, COMPASS };
    screen_order_set(&order, ids, 3);

    TEST_ASSERT_EQUAL_UINT8(SPEED, screen_order_handle_button_press(&order));
    TEST_ASSERT_EQUAL_UINT8(COMPASS, screen_order_handle_button_press(&order));
    TEST_ASSERT_EQUAL_UINT8(NAV, screen_order_handle_button_press(&order));
}

/* ----- set resets current index ----------------------------------------- */

static void test_set_resets_index(void)
{
    screen_order_t order;
    screen_order_init(&order);

    const uint8_t ids1[] = { NAV, COMPASS, CLOCK };
    screen_order_set(&order, ids1, 3);
    screen_order_next(&order); /* -> COMPASS */
    screen_order_next(&order); /* -> CLOCK */

    /* Re-set with a different order: index resets to 0. */
    const uint8_t ids2[] = { WEATHER, SPEED };
    screen_order_set(&order, ids2, 2);
    TEST_ASSERT_EQUAL_UINT8(WEATHER, screen_order_current(&order));
    TEST_ASSERT_EQUAL_UINT8(2, screen_order_count(&order));
}

/* ----- clamping --------------------------------------------------------- */

static void test_count_clamped_to_max(void)
{
    screen_order_t order;
    screen_order_init(&order);

    /* Try to set 20 screens — should be clamped to 13. */
    uint8_t ids[20];
    for (uint8_t i = 0; i < 20; i++) {
        ids[i] = (uint8_t)(i + 1u);
    }
    screen_order_set(&order, ids, 20);
    TEST_ASSERT_EQUAL_UINT8(SCREEN_ORDER_MAX_COUNT, screen_order_count(&order));
}

/* ----- null safety ------------------------------------------------------ */

static void test_null_order_returns_zero(void)
{
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_next(NULL));
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_prev(NULL));
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_current(NULL));
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_count(NULL));
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_first(NULL));
    TEST_ASSERT_EQUAL_UINT8(0, screen_order_handle_button_press(NULL));

    TEST_ASSERT_FALSE(screen_order_set(NULL, NULL, 0));
}

/* ----------------------------------------------------------------------- */

int main(void)
{
    UNITY_BEGIN();

    RUN_TEST(test_init_is_empty);
    RUN_TEST(test_init_null_is_safe);
    RUN_TEST(test_set_order_and_cycle);
    RUN_TEST(test_wrap_around);
    RUN_TEST(test_prev_wraps_around);
    RUN_TEST(test_empty_order_returns_zero);
    RUN_TEST(test_single_screen_order);
    RUN_TEST(test_button_press_advances);
    RUN_TEST(test_set_resets_index);
    RUN_TEST(test_count_clamped_to_max);
    RUN_TEST(test_null_order_returns_zero);

    return UNITY_END();
}
