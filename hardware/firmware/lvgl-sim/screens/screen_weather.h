/*
 * screen_weather.h — weather screen (matches docs/mockups.html "Weather").
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_WEATHER_H
#define SCREEN_WEATHER_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the weather screen layout:
 *   - Condition icon (sun/cloud/rain/snow/fog/thunderstorm) from LVGL shapes
 *   - Hero temperature (e.g. "18°")
 *   - Condition text (e.g. "Partly Cloudy")
 *   - High/Low temperatures
 *   - Location name
 */
void screen_weather_create(lv_obj_t *parent,
                           const ble_weather_data_t *data,
                           uint8_t flags);

#endif /* SCREEN_WEATHER_H */
