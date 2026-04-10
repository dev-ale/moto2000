/*
 * screen_blitzer.h — blitzer/radar warning screen (matches docs/mockups-extra.html).
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_BLITZER_H
#define SCREEN_BLITZER_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the blitzer radar screen layout:
 *   - Concentric radar rings (red, decreasing opacity)
 *   - Speed limit circle (European road-sign style)
 *   - Warning text "CAMERA AHEAD"
 *   - Hero distance (e.g. "380m")
 *   - Camera type label
 *   - Speed comparison pill (current -> limit)
 */
void screen_blitzer_create(lv_obj_t *parent,
                           const ble_blitzer_data_t *data,
                           uint8_t flags);

#endif /* SCREEN_BLITZER_H */
