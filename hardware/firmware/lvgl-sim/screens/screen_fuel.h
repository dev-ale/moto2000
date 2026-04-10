/*
 * screen_fuel.h — fuel estimate screen (matches docs/mockups-extra.html).
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_FUEL_H
#define SCREEN_FUEL_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the fuel estimate screen layout:
 *   - Title "FUEL" (muted gray, top)
 *   - Tank icon with colored fill proportional to tank_percent
 *   - Percentage overlaid on the tank
 *   - Hero range text (e.g. "148km")
 *   - Divider
 *   - Consumption (left) and fuel remaining (right)
 */
void screen_fuel_create(lv_obj_t *parent,
                        const ble_fuel_data_t *data,
                        uint8_t flags);

#endif /* SCREEN_FUEL_H */
