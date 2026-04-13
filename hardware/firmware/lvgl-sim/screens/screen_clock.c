/*
 * screen_clock.c — clock / idle screen (matches docs/mockups.html).
 *
 * Layout (from the SVG mockup):
 *   - Date line at top:     "MI, 9. APRIL"     SCRAM_FONT_LABEL, muted
 *   - Hero time center:     "14:32"             SCRAM_FONT_HERO,  white
 *   - Location + temp:      "Basel — 18°C"     SCRAM_FONT_LABEL, muted
 *   - Status dots at bottom: BLE (green), WiFi (blue) circles with labels
 *
 * Night mode: same layout, red text on black.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_clock.h"
#include "common/screen_manager.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include "ble_protocol.h"
#include "screen_ids.h"

#include <stdio.h>

/* ------------------------------------------------------------------ */
/*  Deterministic time formatting (same algorithm as host-sim).       */
/* ------------------------------------------------------------------ */

static void civil_from_days(int64_t days, int32_t *out_year, uint32_t *out_month, uint32_t *out_day)
{
    days += 719468;
    const int64_t era = (days >= 0 ? days : days - 146096) / 146097;
    const uint32_t doe = (uint32_t)(days - era * 146097);
    const uint32_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const int32_t y = (int32_t)yoe + (int32_t)(era * 400);
    const uint32_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const uint32_t mp = (5 * doy + 2) / 153;
    const uint32_t d = doy - (153 * mp + 2) / 5 + 1;
    const uint32_t m = mp < 10 ? mp + 3 : mp - 9;
    *out_year = y + (int32_t)(m <= 2 ? 1 : 0);
    *out_month = m;
    *out_day = d;
}

static uint32_t weekday_from_days(int64_t days)
{
    int64_t w = (days + 4) % 7;
    if (w < 0) {
        w += 7;
    }
    return (uint32_t)w;
}

static void format_time(const ble_clock_data_t *data, char *buf, size_t cap)
{
    const int64_t local = data->unix_time + (int64_t)data->tz_offset_minutes * 60;
    int64_t sod = local % 86400;
    if (sod < 0)
        sod += 86400;
    int h = (int)(sod / 3600);
    int m = (int)((sod / 60) % 60);

    if (data->is_24h) {
        snprintf(buf, cap, "%02d:%02d", h, m);
    } else {
        int h12 = h % 12;
        if (h12 == 0)
            h12 = 12;
        snprintf(buf, cap, "%d:%02d %s", h12, m, h < 12 ? "AM" : "PM");
    }
}

static void format_date(const ble_clock_data_t *data, char *buf, size_t cap)
{
    const int64_t local = data->unix_time + (int64_t)data->tz_offset_minutes * 60;
    int64_t days = local / 86400;
    int64_t sod = local % 86400;
    if (sod < 0)
        days -= 1;

    int32_t year = 0;
    uint32_t month = 0;
    uint32_t day = 0;
    civil_from_days(days, &year, &month, &day);
    uint32_t wday = weekday_from_days(days);

    /* German abbreviated weekday names (uppercase, matching mockup style). */
    static const char *const wday_de[7] = {
        "SO", "MO", "DI", "MI", "DO", "FR", "SA",
    };
    static const char *const month_de[12] = {
        "JANUAR", "FEBRUAR", "MAERZ",     "APRIL",   "MAI",      "JUNI",
        "JULI",   "AUGUST",  "SEPTEMBER", "OKTOBER", "NOVEMBER", "DEZEMBER",
    };

    (void)year;
    snprintf(buf, cap, "%s, %u. %s", wday_de[wday], (unsigned)day, month_de[month - 1]);
}

/* ------------------------------------------------------------------ */
/*  Screen layout                                                     */
/* ------------------------------------------------------------------ */

void screen_clock_create(lv_obj_t *parent, const ble_clock_data_t *data, uint8_t flags)
{
    (void)flags;
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_WHITE;
    lv_color_t col_muted = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;

    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* --- Date line (top) --- */
    char date_buf[48];
    format_date(data, date_buf, sizeof(date_buf));

    lv_obj_t *lbl_date = lv_label_create(parent);
    lv_label_set_text(lbl_date, date_buf);
    lv_obj_set_style_text_font(lbl_date, SCRAM_FONT_VALUE, 0);
    lv_obj_set_style_text_color(lbl_date, col_muted, 0);
    lv_obj_set_style_text_align(lbl_date, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_date, LV_ALIGN_TOP_MID, 0, 110);

    /* --- Hero time ---
     *
     * Max built-in Montserrat is 48 px. For motorcycle glance-ability on
     * the 466 px AMOLED we scale the label via transform_scale (256 is
     * 1.0x) to get effective ~96 px digits. Montserrat 48 is bold enough
     * that 2x nearest-neighbour stays legible. */
    char time_buf[16];
    format_time(data, time_buf, sizeof(time_buf));

    lv_obj_t *lbl_time = lv_label_create(parent);
    lv_label_set_text(lbl_time, time_buf);
    lv_obj_set_style_text_font(lbl_time, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_time, col_text, 0);
    lv_obj_set_style_text_align(lbl_time, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_transform_pivot_x(lbl_time, LV_PCT(50), 0);
    lv_obj_set_style_transform_pivot_y(lbl_time, LV_PCT(50), 0);
    lv_obj_set_style_transform_scale(lbl_time, 512, 0); /* 2.0x */
    lv_obj_align(lbl_time, LV_ALIGN_CENTER, 0, 0);

    /* --- Location + temperature ---
     *
     * Pull the most recent weather payload from the screen-manager cache
     * (iOS streams it on its own cadence, ~10 min). If nothing is cached
     * yet — first boot, no GPS fix, no network — render nothing rather
     * than a placeholder, so the clock screen stays clean. */
    uint8_t weather_buf[BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_WEATHER_BODY_SIZE];
    size_t weather_len = 0;
    if (screen_manager_get_cached(BLE_SCREEN_WEATHER, weather_buf, sizeof(weather_buf),
                                  &weather_len)) {
        ble_weather_data_t w;
        uint8_t wflags = 0;
        if (ble_decode_weather(weather_buf, weather_len, &wflags, &w) == BLE_OK &&
            w.location_name[0] != '\0') {
            char ws[48];
            int t =
                (int)((w.temperature_celsius_x10 + (w.temperature_celsius_x10 >= 0 ? 5 : -5)) / 10);
            /* Use ASCII-safe degree marker: Montserrat doesn't include
             * the U+00B0 ° glyph and renders a missing-glyph box. */
            snprintf(ws, sizeof(ws), "%s  %d C", w.location_name, t);

            lv_obj_t *lbl_w = lv_label_create(parent);
            lv_label_set_text(lbl_w, ws);
            lv_obj_set_style_text_font(lbl_w, SCRAM_FONT_VALUE, 0);
            lv_obj_set_style_text_color(lbl_w, col_muted, 0);
            lv_obj_set_style_text_align(lbl_w, LV_TEXT_ALIGN_CENTER, 0);
            lv_obj_align(lbl_w, LV_ALIGN_BOTTOM_MID, 0, -110);
        }
    }
}
