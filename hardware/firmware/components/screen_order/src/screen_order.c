/*
 * screen_order.c — implementation. See include/screen_order.h for the API.
 */
#include "screen_order.h"

#include <string.h>

void screen_order_init(screen_order_t *order)
{
    if (order == NULL) {
        return;
    }
    memset(order, 0, sizeof(*order));
}

bool screen_order_set(screen_order_t *order, const uint8_t *ids, uint8_t count)
{
    if (order == NULL || ids == NULL) {
        return false;
    }

    uint8_t actual = count;
    if (actual > SCREEN_ORDER_MAX_COUNT) {
        actual = SCREEN_ORDER_MAX_COUNT;
    }

    memcpy(order->ids, ids, actual);
    order->count = actual;
    order->current_index = 0;
    return true;
}

uint8_t screen_order_next(screen_order_t *order)
{
    if (order == NULL || order->count == 0) {
        return 0;
    }
    order->current_index = (uint8_t)((order->current_index + 1u) % order->count);
    return order->ids[order->current_index];
}

uint8_t screen_order_prev(screen_order_t *order)
{
    if (order == NULL || order->count == 0) {
        return 0;
    }
    if (order->current_index == 0) {
        order->current_index = (uint8_t)(order->count - 1u);
    } else {
        order->current_index = (uint8_t)(order->current_index - 1u);
    }
    return order->ids[order->current_index];
}

uint8_t screen_order_current(const screen_order_t *order)
{
    if (order == NULL || order->count == 0) {
        return 0;
    }
    return order->ids[order->current_index];
}

uint8_t screen_order_count(const screen_order_t *order)
{
    if (order == NULL) {
        return 0;
    }
    return order->count;
}

uint8_t screen_order_first(const screen_order_t *order)
{
    if (order == NULL || order->count == 0) {
        return 0;
    }
    return order->ids[0];
}

uint8_t screen_order_handle_button_press(screen_order_t *order)
{
    return screen_order_next(order);
}
