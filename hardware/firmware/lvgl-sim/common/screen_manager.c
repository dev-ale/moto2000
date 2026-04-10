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
#include "screens/screen_weather.h"
#include "screens/screen_music.h"
#include "screens/screen_trip_stats.h"
#include "screens/screen_lean_angle.h"
#include "screens/screen_altitude.h"
#include "screens/screen_calendar.h"
#include "screens/screen_fuel.h"
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
        case BLE_SCREEN_WEATHER: {
            ble_weather_data_t weather;
            uint8_t weather_flags = 0;
            rc = ble_decode_weather(data, len, &weather_flags, &weather);
            if (rc != BLE_OK) {
                fprintf(stderr, "lvgl-sim: weather decode failed: %s\n",
                        ble_result_name(rc));
                screen_placeholder_create(scr, "WEATHER (decode error)");
                break;
            }
            screen_weather_create(scr, &weather, weather_flags);
            break;
        }
        case BLE_SCREEN_TRIP_STATS: {
            ble_trip_stats_data_t trip;
            uint8_t trip_flags = 0;
            rc = ble_decode_trip_stats(data, len, &trip_flags, &trip);
            if (rc != BLE_OK) {
                fprintf(stderr, "lvgl-sim: trip_stats decode failed: %s\n",
                        ble_result_name(rc));
                screen_placeholder_create(scr, "TRIP STATS (decode error)");
                break;
            }
            screen_trip_stats_create(scr, &trip, trip_flags);
            break;
        }
        case BLE_SCREEN_MUSIC: {
            ble_music_data_t music;
            uint8_t music_flags = 0;
            rc = ble_decode_music(data, len, &music_flags, &music);
            if (rc != BLE_OK) {
                fprintf(stderr, "lvgl-sim: music decode failed: %s\n",
                        ble_result_name(rc));
                screen_placeholder_create(scr, "MUSIC (decode error)");
                break;
            }
            screen_music_create(scr, &music, music_flags);
            break;
        }
        case BLE_SCREEN_LEAN_ANGLE: {
            ble_lean_angle_data_t lean;
            uint8_t lean_flags = 0;
            rc = ble_decode_lean_angle(data, len, &lean_flags, &lean);
            if (rc != BLE_OK) {
                fprintf(stderr, "lvgl-sim: lean_angle decode failed: %s\n",
                        ble_result_name(rc));
                screen_placeholder_create(scr, "LEAN ANGLE (decode error)");
                break;
            }
            screen_lean_angle_create(scr, &lean, lean_flags);
            break;
        }
        case BLE_SCREEN_BLITZER:
            screen_placeholder_create(scr, "BLITZER");
            break;
        case BLE_SCREEN_INCOMING_CALL:
            screen_placeholder_create(scr, "INCOMING CALL");
            break;
        case BLE_SCREEN_FUEL_ESTIMATE: {
            ble_fuel_data_t fuel;
            uint8_t fuel_flags = 0;
            rc = ble_decode_fuel(data, len, &fuel_flags, &fuel);
            if (rc != BLE_OK) {
                fprintf(stderr, "lvgl-sim: fuel decode failed: %s\n",
                        ble_result_name(rc));
                screen_placeholder_create(scr, "FUEL (decode error)");
                break;
            }
            screen_fuel_create(scr, &fuel, fuel_flags);
            break;
        }
        case BLE_SCREEN_ALTITUDE: {
            ble_altitude_profile_data_t altitude;
            uint8_t alt_flags = 0;
            rc = ble_decode_altitude(data, len, &alt_flags, &altitude);
            if (rc != BLE_OK) {
                fprintf(stderr, "lvgl-sim: altitude decode failed: %s\n",
                        ble_result_name(rc));
                screen_placeholder_create(scr, "ALTITUDE (decode error)");
                break;
            }
            screen_altitude_create(scr, &altitude, alt_flags);
            break;
        }
        case BLE_SCREEN_APPOINTMENT: {
            ble_appointment_data_t appt;
            uint8_t appt_flags = 0;
            rc = ble_decode_appointment(data, len, &appt_flags, &appt);
            if (rc != BLE_OK) {
                fprintf(stderr, "lvgl-sim: appointment decode failed: %s\n",
                        ble_result_name(rc));
                screen_placeholder_create(scr, "APPOINTMENT (decode error)");
                break;
            }
            screen_calendar_create(scr, &appt, appt_flags);
            break;
        }
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
