/*
 * screen_altitude.h — altitude profile screen (matches docs/mockups-extra.html).
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_ALTITUDE_H
#define SCREEN_ALTITUDE_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the altitude profile screen layout:
 *   - Title "ALTITUDE" (muted gray, top)
 *   - Hero altitude value (e.g. "1248M")
 *   - Status line (e.g. "+86M TO PEAK")
 *   - Elevation profile line chart (green traveled, gray future)
 *   - Current position dot with dashed vertical line
 *   - X-axis distance labels
 *   - Ascent/descent totals at the bottom
 */
void screen_altitude_create(lv_obj_t *parent,
                            const ble_altitude_profile_data_t *data,
                            uint8_t flags);

#endif /* SCREEN_ALTITUDE_H */
