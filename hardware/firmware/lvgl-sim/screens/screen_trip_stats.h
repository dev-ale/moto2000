/*
 * screen_trip_stats.h — trip statistics screen (matches docs/mockups.html "Trip stats").
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_TRIP_STATS_H
#define SCREEN_TRIP_STATS_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the trip stats screen layout:
 *   - "ACTIVE RIDE" header (green accent)
 *   - Hero duration (e.g. "1:42h")
 *   - "Ride time" subtitle
 *   - Distance + average speed (grid, left/right columns)
 *   - Elevation (orange) + max speed (blue) bottom row
 */
void screen_trip_stats_create(lv_obj_t *parent,
                              const ble_trip_stats_data_t *data,
                              uint8_t flags);

#endif /* SCREEN_TRIP_STATS_H */
