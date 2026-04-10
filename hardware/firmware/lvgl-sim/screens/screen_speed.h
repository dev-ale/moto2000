/*
 * screen_speed.h — speed + heading screen (matches docs/mockups.html).
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_SPEED_H
#define SCREEN_SPEED_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the speed + heading screen layout:
 *   - Arc gauge ring (0-300 km/h, ~270 deg)
 *   - Hero speed digits (e.g. "67")
 *   - Unit label ("km/h")
 *   - Heading with cardinal direction (e.g. "NE 042")
 *   - Altitude (left) and temperature (right) at the bottom
 */
void screen_speed_create(lv_obj_t *parent, const ble_speed_heading_data_t *data, uint8_t flags);

#endif /* SCREEN_SPEED_H */
