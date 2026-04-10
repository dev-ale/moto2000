/*
 * screen_navigation.h — turn-by-turn navigation screen (matches docs/mockups.html).
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_NAVIGATION_H
#define SCREEN_NAVIGATION_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the navigation screen layout:
 *   - Hero turn arrow (green, upper 40%, derived from maneuver_type)
 *   - Street name (muted gray, centered)
 *   - Distance to next maneuver (large white hero text)
 *   - Maneuver description (green accent, small)
 *   - ETA + remaining distance (muted gray, bottom)
 *
 * Night mode: green arrows become red, text follows theme palette.
 */
void screen_navigation_create(lv_obj_t *parent, const ble_nav_data_t *nav, uint8_t flags);

#endif /* SCREEN_NAVIGATION_H */
