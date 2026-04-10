/*
 * screen_lean_angle.h — lean angle screen (matches docs/mockups-extra.html).
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_LEAN_ANGLE_H
#define SCREEN_LEAN_ANGLE_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the lean angle screen layout:
 *   - Title "LEAN" (muted gray, top)
 *   - Arc gauge spanning ~180 deg with green/orange zones
 *   - Needle pointing to current lean angle
 *   - Digital readout (e.g. "24 deg")
 *   - Direction label (LEFT / RIGHT)
 *   - Max indicators for left and right
 */
void screen_lean_angle_create(lv_obj_t *parent,
                              const ble_lean_angle_data_t *data,
                              uint8_t flags);

#endif /* SCREEN_LEAN_ANGLE_H */
