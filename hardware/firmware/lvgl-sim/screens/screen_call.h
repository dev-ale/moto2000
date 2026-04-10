/*
 * screen_call.h — incoming call screen (matches docs/mockups-extra.html).
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_CALL_H
#define SCREEN_CALL_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the incoming call screen layout:
 *   - Static glow ring around the avatar
 *   - Avatar circle with caller initial
 *   - Caller name
 *   - State text (INCOMING CALL / CONNECTED / CALL ENDED)
 *   - Decorative accept/reject buttons
 */
void screen_call_create(lv_obj_t *parent,
                        const ble_incoming_call_data_t *data,
                        uint8_t flags);

#endif /* SCREEN_CALL_H */
