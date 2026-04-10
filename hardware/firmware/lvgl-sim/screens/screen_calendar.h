/*
 * screen_calendar.h — calendar/appointment screen (matches docs/mockups-extra.html).
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_CALENDAR_H
#define SCREEN_CALENDAR_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the calendar event screen layout:
 *   - Title "NEXT EVENT" (muted gray, top)
 *   - Event card with colored left border containing title, time, location
 *   - Countdown (e.g. "IN 42M", "NOW", "15M AGO")
 */
void screen_calendar_create(lv_obj_t *parent,
                            const ble_appointment_data_t *data,
                            uint8_t flags);

#endif /* SCREEN_CALENDAR_H */
