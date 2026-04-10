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
#include "screens/screen_blitzer.h"
#include "screens/screen_call.h"
#include "screens/screen_fuel.h"
#include "screens/screen_placeholder.h"
#include "theme/scram_theme.h"

#include "ble_protocol.h"
#include "lvgl.h"

#include <stdio.h>
#include <string.h>

#define MAX_CACHED_PAYLOAD 4096U
#define MAX_SCREENS        16

/* Cached payload per screen ID. */
static struct {
    uint8_t data[MAX_CACHED_PAYLOAD];
    size_t len;
    bool valid;
} s_cache[MAX_SCREENS];

/* Ordered list of screen IDs that have cached data. */
static uint8_t s_active_ids[MAX_SCREENS];
static int s_active_count = 0;
static int s_current_idx = 0;
static bool s_night_mode = false;

static void render_current(void);

static void rebuild_active_list(void)
{
    s_active_count = 0;
    for (int i = 0; i < MAX_SCREENS; i++) {
        if (s_cache[i].valid) {
            s_active_ids[s_active_count++] = (uint8_t)i;
        }
    }
}

void screen_manager_init(void)
{
    memset(s_cache, 0, sizeof(s_cache));
    s_active_count = 0;
    s_current_idx = 0;
    s_night_mode = false;
}

void screen_manager_handle_payload(const uint8_t *data, size_t len)
{
    if (data == NULL || len == 0) {
        return;
    }

    ble_header_t header;
    ble_result_t rc = ble_decode_header(data, len, &header);
    if (rc != BLE_OK) {
        fprintf(stderr, "lvgl-sim: header decode failed: %s\n", ble_result_name(rc));
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
            fprintf(stderr, "lvgl-sim: clock decode failed: %s\n", ble_result_name(rc));
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
            fprintf(stderr, "lvgl-sim: nav decode failed: %s\n", ble_result_name(rc));
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
            fprintf(stderr, "lvgl-sim: speed_heading decode failed: %s\n", ble_result_name(rc));
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
            fprintf(stderr, "lvgl-sim: compass decode failed: %s\n", ble_result_name(rc));
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
            fprintf(stderr, "lvgl-sim: weather decode failed: %s\n", ble_result_name(rc));
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
            fprintf(stderr, "lvgl-sim: trip_stats decode failed: %s\n", ble_result_name(rc));
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
            fprintf(stderr, "lvgl-sim: music decode failed: %s\n", ble_result_name(rc));
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
            fprintf(stderr, "lvgl-sim: lean_angle decode failed: %s\n", ble_result_name(rc));
            screen_placeholder_create(scr, "LEAN ANGLE (decode error)");
            break;
        }
        screen_lean_angle_create(scr, &lean, lean_flags);
        break;
    }
    case BLE_SCREEN_BLITZER: {
        ble_blitzer_data_t blitzer;
        uint8_t blitzer_flags = 0;
        rc = ble_decode_blitzer(data, len, &blitzer_flags, &blitzer);
        if (rc != BLE_OK) {
            fprintf(stderr, "lvgl-sim: blitzer decode failed: %s\n", ble_result_name(rc));
            screen_placeholder_create(scr, "BLITZER (decode error)");
            break;
        }
        screen_blitzer_create(scr, &blitzer, blitzer_flags);
        break;
    }
    case BLE_SCREEN_INCOMING_CALL: {
        ble_incoming_call_data_t call;
        uint8_t call_flags = 0;
        rc = ble_decode_incoming_call(data, len, &call_flags, &call);
        if (rc != BLE_OK) {
            fprintf(stderr, "lvgl-sim: incoming_call decode failed: %s\n", ble_result_name(rc));
            screen_placeholder_create(scr, "CALL (decode error)");
            break;
        }
        screen_call_create(scr, &call, call_flags);
        break;
    }
    case BLE_SCREEN_FUEL_ESTIMATE: {
        ble_fuel_data_t fuel;
        uint8_t fuel_flags = 0;
        rc = ble_decode_fuel(data, len, &fuel_flags, &fuel);
        if (rc != BLE_OK) {
            fprintf(stderr, "lvgl-sim: fuel decode failed: %s\n", ble_result_name(rc));
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
            fprintf(stderr, "lvgl-sim: altitude decode failed: %s\n", ble_result_name(rc));
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
            fprintf(stderr, "lvgl-sim: appointment decode failed: %s\n", ble_result_name(rc));
            screen_placeholder_create(scr, "APPOINTMENT (decode error)");
            break;
        }
        screen_calendar_create(scr, &appt, appt_flags);
        break;
    }
    default: {
        char name[32];
        snprintf(name, sizeof(name), "UNKNOWN (0x%02X)", (unsigned)header.screen_id);
        screen_placeholder_create(scr, name);
        break;
    }
    }

    lv_screen_load(scr);
}

void screen_manager_cache_payload(const uint8_t *data, size_t len)
{
    if (data == NULL || len == 0 || len > MAX_CACHED_PAYLOAD)
        return;

    ble_header_t header;
    ble_result_t rc = ble_decode_header(data, len, &header);
    if (rc != BLE_OK)
        return;

    uint8_t id = header.screen_id;
    if (id >= MAX_SCREENS)
        return;

    memcpy(s_cache[id].data, data, len);
    s_cache[id].len = len;
    s_cache[id].valid = true;
    rebuild_active_list();
}

void screen_manager_update_live(const uint8_t *data, size_t len)
{
    if (data == NULL || len == 0 || len > MAX_CACHED_PAYLOAD)
        return;

    ble_header_t header;
    ble_result_t rc = ble_decode_header(data, len, &header);
    if (rc != BLE_OK)
        return;

    uint8_t id = header.screen_id;
    if (id >= MAX_SCREENS)
        return;

    bool was_empty = (s_active_count == 0);
    memcpy(s_cache[id].data, data, len);
    s_cache[id].len = len;
    s_cache[id].valid = true;
    rebuild_active_list();

    /* Render if this is the currently selected screen, or if it's the
     * very first payload (so the user sees something immediately). */
    if (was_empty) {
        /* First data — find this screen's index and display it. */
        for (int i = 0; i < s_active_count; i++) {
            if (s_active_ids[i] == id) {
                s_current_idx = i;
                break;
            }
        }
        render_current();
    } else if (s_current_idx < s_active_count && s_active_ids[s_current_idx] == id) {
        /* Update the currently displayed screen with fresh data. */
        render_current();
    }
}

static void render_current(void)
{
    if (s_active_count == 0)
        return;
    if (s_current_idx >= s_active_count)
        s_current_idx = 0;

    uint8_t id = s_active_ids[s_current_idx];

    /* Patch night-mode flag into the cached payload. */
    uint8_t patched[MAX_CACHED_PAYLOAD];
    memcpy(patched, s_cache[id].data, s_cache[id].len);
    if (s_cache[id].len >= 3) {
        if (s_night_mode)
            patched[2] |= BLE_FLAG_NIGHT_MODE;
        else
            patched[2] &= (uint8_t)~BLE_FLAG_NIGHT_MODE;
    }

    screen_manager_handle_payload(patched, s_cache[id].len);

    /* Print which screen is active. */
    const char *names[] = {
        [BLE_SCREEN_CLOCK] = "Clock",           [BLE_SCREEN_NAVIGATION] = "Navigation",
        [BLE_SCREEN_SPEED_HEADING] = "Speed",   [BLE_SCREEN_COMPASS] = "Compass",
        [BLE_SCREEN_TRIP_STATS] = "Trip Stats", [BLE_SCREEN_WEATHER] = "Weather",
        [BLE_SCREEN_LEAN_ANGLE] = "Lean Angle", [BLE_SCREEN_MUSIC] = "Music",
        [BLE_SCREEN_APPOINTMENT] = "Calendar",  [BLE_SCREEN_FUEL_ESTIMATE] = "Fuel",
        [BLE_SCREEN_ALTITUDE] = "Altitude",     [BLE_SCREEN_INCOMING_CALL] = "Call",
        [BLE_SCREEN_BLITZER] = "Blitzer",
    };
    const char *name = (id < sizeof(names) / sizeof(names[0]) && names[id]) ? names[id] : "Unknown";
    fprintf(stderr, "[%d/%d] %s%s\n", s_current_idx + 1, s_active_count, name,
            s_night_mode ? " (night)" : "");
}

void screen_manager_next_screen(void)
{
    if (s_active_count == 0)
        return;
    s_current_idx = (s_current_idx + 1) % s_active_count;
    render_current();
}

void screen_manager_prev_screen(void)
{
    if (s_active_count == 0)
        return;
    s_current_idx = (s_current_idx - 1 + s_active_count) % s_active_count;
    render_current();
}

void screen_manager_toggle_night(void)
{
    s_night_mode = !s_night_mode;
    render_current();
}
