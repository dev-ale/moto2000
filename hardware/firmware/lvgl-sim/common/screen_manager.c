/*
 * screen_manager.c — dispatches BLE payloads to LVGL screen implementations.
 *
 * Decodes the BLE header, checks for NIGHT_MODE, and dispatches to the
 * appropriate screen's create function. Falls back to screen_placeholder
 * for screen IDs that don't have a real LVGL implementation yet.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "common/screen_manager.h"
#include "screens/screen_clock.h"
#include "screens/screen_speed.h"
#include "screens/screen_compass.h"
#include "screens/screen_navigation.h"
#include "screens/screen_placeholder.h"
#include "theme/scram_theme.h"

#include "ble_protocol.h"
#include "lvgl.h"

#include <stdio.h>

void screen_manager_init(void)
{
    /* Nothing to initialise yet. Reserved for future state tracking. */
}

void screen_manager_handle_payload(const uint8_t *data, size_t len)
{
    if (data == NULL || len == 0) {
        return;
    }

    ble_header_t header;
    ble_result_t rc = ble_decode_header(data, len, &header);
    if (rc != BLE_OK) {
        fprintf(stderr, "lvgl-sim: header decode failed: %s\n",
                ble_result_name(rc));
        return;
    }

    /* Check NIGHT_MODE flag and update theme accordingly. */
    bool night = (header.flags & BLE_FLAG_NIGHT_MODE) != 0;
    scram_theme_set_night_mode(night);

    /* Create a fresh screen. */
    lv_obj_t *scr = lv_obj_create(NULL);

    switch (header.screen_id) {
        case BLE_SCREEN_CLOCK: {
            ble_clock_data_t clock_data;
            uint8_t flags = 0;
            rc = ble_decode_clock(data, len, &flags, &clock_data);
            if (rc != BLE_OK) {
                fprintf(stderr, "lvgl-sim: clock decode failed: %s\n",
                        ble_result_name(rc));
                screen_placeholder_create(scr, "CLOCK (decode error)");
                break;
            }
            screen_clock_create(scr, &clock_data, flags);
            break;
        }

        case BLE_SCREEN_NAVIGATION: {
            ble_nav_data_t nav;
            uint8_t nav_flags = 0;
            rc = ble_decode_nav(data, len, &nav_flags, &nav);
            if (rc != BLE_OK) {
                fprintf(stderr, "lvgl-sim: nav decode failed: %s\n",
                        ble_result_name(rc));
                screen_placeholder_create(scr, "NAV (decode error)");
                break;
            }
            screen_navigation_create(scr, &nav, nav_flags);
            break;
        }
        case BLE_SCREEN_SPEED_HEADING: {
            ble_speed_heading_data_t speed;
            uint8_t speed_flags = 0;
            rc = ble_decode_speed_heading(data, len, &speed_flags, &speed);
            if (rc != BLE_OK) {
                fprintf(stderr, "lvgl-sim: speed_heading decode failed: %s\n",
                        ble_result_name(rc));
                screen_placeholder_create(scr, "SPEED (decode error)");
                break;
            }
            screen_speed_create(scr, &speed, speed_flags);
            break;
        }
        case BLE_SCREEN_COMPASS: {
            ble_compass_data_t compass;
            uint8_t compass_flags = 0;
            rc = ble_decode_compass(data, len, &compass_flags, &compass);
            if (rc != BLE_OK) {
                fprintf(stderr, "lvgl-sim: compass decode failed: %s\n",
                        ble_result_name(rc));
                screen_placeholder_create(scr, "COMPASS (decode error)");
                break;
            }
            screen_compass_create(scr, &compass, compass_flags);
            break;
        }
        case BLE_SCREEN_WEATHER:
            screen_placeholder_create(scr, "WEATHER");
            break;
        case BLE_SCREEN_TRIP_STATS:
            screen_placeholder_create(scr, "TRIP STATS");
            break;
        case BLE_SCREEN_MUSIC:
            screen_placeholder_create(scr, "MUSIC");
            break;
        case BLE_SCREEN_LEAN_ANGLE:
            screen_placeholder_create(scr, "LEAN ANGLE");
            break;
        case BLE_SCREEN_BLITZER:
            screen_placeholder_create(scr, "BLITZER");
            break;
        case BLE_SCREEN_INCOMING_CALL:
            screen_placeholder_create(scr, "INCOMING CALL");
            break;
        case BLE_SCREEN_FUEL_ESTIMATE:
            screen_placeholder_create(scr, "FUEL ESTIMATE");
            break;
        case BLE_SCREEN_ALTITUDE:
            screen_placeholder_create(scr, "ALTITUDE");
            break;
        case BLE_SCREEN_APPOINTMENT:
            screen_placeholder_create(scr, "APPOINTMENT");
            break;
        default: {
            char name[32];
            snprintf(name, sizeof(name), "UNKNOWN (0x%02X)",
                     (unsigned)header.screen_id);
            screen_placeholder_create(scr, name);
            break;
        }
    }

    lv_screen_load(scr);
}
