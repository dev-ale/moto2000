/*
 * screen_clock.h — clock / idle screen (matches docs/mockups.html "Idle / clock").
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_CLOCK_H
#define SCREEN_CLOCK_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the clock screen layout:
 *   - Date line at top (e.g. "MI, 9. APRIL")
 *   - Hero time digits (e.g. "14:32")
 *   - Location + temperature (e.g. "Basel — 18°C")
 *   - Status dots (BLE, WiFi)
 */
void screen_clock_create(lv_obj_t *parent, const ble_clock_data_t *data, uint8_t flags);

#endif /* SCREEN_CLOCK_H */
