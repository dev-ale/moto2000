/*
 * screen_compass.h — compass screen with rotating dial (matches docs/mockups.html).
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_COMPASS_H
#define SCREEN_COMPASS_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the compass screen layout:
 *   - Outer ring (subtle gray circle)
 *   - Tick marks at 30-degree intervals, rotated by heading
 *   - Cardinal labels N (red), E, S, W (gray), positioned around ring
 *   - Classic red/gray diamond needle pointing to magnetic north
 *   - Digital heading readout (e.g. "042")
 *   - MAG/TRU indicator
 */
void screen_compass_create(lv_obj_t *parent, const ble_compass_data_t *data, uint8_t flags);

#endif /* SCREEN_COMPASS_H */
