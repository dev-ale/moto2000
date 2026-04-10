/*
 * screen_order.h — ordered list of enabled screens + navigation.
 *
 * Receives the screen ordering from the iOS app via setScreenOrder and
 * provides next/prev navigation for handlebar button presses.
 *
 * Pure C, no ESP-IDF dependencies.
 */
#ifndef SCRAMSCREEN_SCREEN_ORDER_H
#define SCRAMSCREEN_SCREEN_ORDER_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Maximum number of screens in an order list (one per screen ID). */
#define SCREEN_ORDER_MAX_COUNT ((uint8_t)13u)

typedef struct {
    uint8_t ids[SCREEN_ORDER_MAX_COUNT];
    uint8_t count;
    uint8_t current_index;
} screen_order_t;

/*
 * Initialise to an empty screen order.
 */
void screen_order_init(screen_order_t *order);

/*
 * Set the screen order from a setScreenOrder BLE command.
 * count is clamped to SCREEN_ORDER_MAX_COUNT.
 * Resets the current index to 0.
 * Returns false if order or ids is NULL.
 */
bool screen_order_set(screen_order_t *order, const uint8_t *ids, uint8_t count);

/*
 * Advance to the next screen in the order (wraps around).
 * Returns the new current screen ID, or 0 if the order is empty.
 */
uint8_t screen_order_next(screen_order_t *order);

/*
 * Go to the previous screen in the order (wraps around).
 * Returns the new current screen ID, or 0 if the order is empty.
 */
uint8_t screen_order_prev(screen_order_t *order);

/*
 * Return the current screen ID, or 0 if the order is empty.
 */
uint8_t screen_order_current(const screen_order_t *order);

/*
 * Return the number of screens in the order.
 */
uint8_t screen_order_count(const screen_order_t *order);

/*
 * Return the first screen in the order, or 0 if empty.
 */
uint8_t screen_order_first(const screen_order_t *order);

/*
 * Handle a handlebar button press: advance to the next screen and return
 * the new screen ID. Equivalent to screen_order_next().
 * Returns 0 if the order is empty.
 */
uint8_t screen_order_handle_button_press(screen_order_t *order);

#ifdef __cplusplus
}
#endif

#endif /* SCRAMSCREEN_SCREEN_ORDER_H */
