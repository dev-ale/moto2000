/*
 * screen_trip_stats.c — trip stats screen with grid layout (matches docs/mockups.html).
 *
 * Layout (from the SVG mockup "Trip stats"):
 *   - Header:       "ACTIVE RIDE"    SCRAM_FONT_SMALL, accent green
 *   - Hero time:    "1:42h"          SCRAM_FONT_HERO (scaled down), white
 *   - Subtitle:     "Ride time"      SCRAM_FONT_SMALL, muted gray
 *   - Horizontal divider line
 *   - Left column:  "87.3" + "km"    SCRAM_FONT_VALUE + SCRAM_FONT_SMALL
 *   - Right column: "51" + "avg km/h"
 *   - Vertical divider between columns
 *   - Bottom left:  "1420m" (orange) + "Elevation"
 *   - Bottom right: "94" (blue) + "max km/h"
 *
 * Night mode: red palette.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_trip_stats.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <stdio.h>

/* ------------------------------------------------------------------ */
/*  Duration formatting                                                */
/* ------------------------------------------------------------------ */

static void format_duration(uint32_t seconds, char *buf, size_t cap)
{
    if (seconds < 60U) {
        snprintf(buf, cap, "0:%02u", (unsigned)seconds);
    } else if (seconds < 3600U) {
        unsigned m = (unsigned)(seconds / 60U);
        unsigned s = (unsigned)(seconds % 60U);
        snprintf(buf, cap, "%u:%02u", m, s);
    } else {
        unsigned h = (unsigned)(seconds / 3600U);
        unsigned m = (unsigned)((seconds % 3600U) / 60U);
        snprintf(buf, cap, "%u:%02uh", h, m);
    }
}

/* ------------------------------------------------------------------ */
/*  Divider helpers                                                     */
/* ------------------------------------------------------------------ */

static void create_h_divider(lv_obj_t *parent, int y_offset, lv_color_t col)
{
    lv_obj_t *line = lv_obj_create(parent);
    lv_obj_set_size(line, 280, 1);
    lv_obj_set_style_bg_color(line, col, 0);
    lv_obj_set_style_bg_opa(line, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(line, 0, 0);
    lv_obj_set_style_radius(line, 0, 0);
    lv_obj_clear_flag(line, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(line, LV_ALIGN_CENTER, 0, y_offset);
}

static void create_v_divider(lv_obj_t *parent, int y_offset, int height, lv_color_t col)
{
    lv_obj_t *line = lv_obj_create(parent);
    lv_obj_set_size(line, 1, height);
    lv_obj_set_style_bg_color(line, col, 0);
    lv_obj_set_style_bg_opa(line, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(line, 0, 0);
    lv_obj_set_style_radius(line, 0, 0);
    lv_obj_clear_flag(line, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(line, LV_ALIGN_CENTER, 0, y_offset);
}

/* ------------------------------------------------------------------ */
/*  Screen layout                                                      */
/* ------------------------------------------------------------------ */

void screen_trip_stats_create(lv_obj_t *parent, const ble_trip_stats_data_t *data, uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_WHITE;
    lv_color_t col_muted = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_green = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_GREEN;
    lv_color_t col_orange = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_ORANGE;
    lv_color_t col_blue = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_BLUE;
    lv_color_t col_div = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_INACTIVE;

    (void)flags;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* --- Header: "ACTIVE RIDE" --- */
    lv_obj_t *lbl_header = lv_label_create(parent);
    lv_label_set_text(lbl_header, "ACTIVE RIDE");
    lv_obj_set_style_text_font(lbl_header, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_header, col_green, 0);
    lv_obj_set_style_text_align(lbl_header, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_header, LV_ALIGN_TOP_MID, 0, 75);

    /* --- Hero duration --- */
    char dur_buf[16];
    format_duration(data->ride_time_seconds, dur_buf, sizeof(dur_buf));

    lv_obj_t *lbl_dur = lv_label_create(parent);
    lv_label_set_text(lbl_dur, dur_buf);
    lv_obj_set_style_text_font(lbl_dur, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_dur, col_text, 0);
    lv_obj_set_style_text_align(lbl_dur, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_dur, LV_ALIGN_CENTER, 0, -55);

    /* --- "Ride time" subtitle --- */
    lv_obj_t *lbl_sub = lv_label_create(parent);
    lv_label_set_text(lbl_sub, "Ride time");
    lv_obj_set_style_text_font(lbl_sub, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_sub, col_muted, 0);
    lv_obj_set_style_text_align(lbl_sub, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_sub, LV_ALIGN_CENTER, 0, -20);

    /* --- Horizontal divider --- */
    create_h_divider(parent, 0, col_div);

    /* --- Distance (left column) --- */
    double dist_km = (double)data->distance_meters / 1000.0;
    char dist_buf[16];
    if (dist_km < 100.0) {
        snprintf(dist_buf, sizeof(dist_buf), "%.1f", dist_km);
    } else {
        snprintf(dist_buf, sizeof(dist_buf), "%.0f", dist_km);
    }

    lv_obj_t *lbl_dist = lv_label_create(parent);
    lv_label_set_text(lbl_dist, dist_buf);
    lv_obj_set_style_text_font(lbl_dist, SCRAM_FONT_VALUE, 0);
    lv_obj_set_style_text_color(lbl_dist, col_text, 0);
    lv_obj_set_style_text_align(lbl_dist, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_dist, LV_ALIGN_CENTER, -80, 30);

    lv_obj_t *lbl_dist_unit = lv_label_create(parent);
    lv_label_set_text(lbl_dist_unit, "km");
    lv_obj_set_style_text_font(lbl_dist_unit, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_dist_unit, col_muted, 0);
    lv_obj_set_style_text_align(lbl_dist_unit, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_dist_unit, LV_ALIGN_CENTER, -80, 55);

    /* --- Average speed (right column) --- */
    uint16_t avg_kmh = data->average_speed_kmh_x10 / 10;
    char avg_buf[8];
    snprintf(avg_buf, sizeof(avg_buf), "%u", (unsigned)avg_kmh);

    lv_obj_t *lbl_avg = lv_label_create(parent);
    lv_label_set_text(lbl_avg, avg_buf);
    lv_obj_set_style_text_font(lbl_avg, SCRAM_FONT_VALUE, 0);
    lv_obj_set_style_text_color(lbl_avg, col_text, 0);
    lv_obj_set_style_text_align(lbl_avg, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_avg, LV_ALIGN_CENTER, 80, 30);

    lv_obj_t *lbl_avg_unit = lv_label_create(parent);
    lv_label_set_text(lbl_avg_unit, "avg km/h");
    lv_obj_set_style_text_font(lbl_avg_unit, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_avg_unit, col_muted, 0);
    lv_obj_set_style_text_align(lbl_avg_unit, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_avg_unit, LV_ALIGN_CENTER, 80, 55);

    /* --- Vertical divider between columns --- */
    create_v_divider(parent, 30, 70, col_div);

    /* --- Elevation (bottom left, orange) --- */
    char elev_buf[16];
    snprintf(elev_buf, sizeof(elev_buf), "%um", (unsigned)data->ascent_meters);

    lv_obj_t *lbl_elev = lv_label_create(parent);
    lv_label_set_text(lbl_elev, elev_buf);
    lv_obj_set_style_text_font(lbl_elev, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_elev, col_orange, 0);
    lv_obj_set_style_text_align(lbl_elev, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_elev, LV_ALIGN_CENTER, -80, 90);

    lv_obj_t *lbl_elev_sub = lv_label_create(parent);
    lv_label_set_text(lbl_elev_sub, "Elevation");
    lv_obj_set_style_text_font(lbl_elev_sub, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_elev_sub, col_muted, 0);
    lv_obj_set_style_text_align(lbl_elev_sub, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_elev_sub, LV_ALIGN_CENTER, -80, 110);

    /* --- Max speed (bottom right, blue) --- */
    uint16_t max_kmh = data->max_speed_kmh_x10 / 10;
    char max_buf[8];
    snprintf(max_buf, sizeof(max_buf), "%u", (unsigned)max_kmh);

    lv_obj_t *lbl_max = lv_label_create(parent);
    lv_label_set_text(lbl_max, max_buf);
    lv_obj_set_style_text_font(lbl_max, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_max, col_blue, 0);
    lv_obj_set_style_text_align(lbl_max, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_max, LV_ALIGN_CENTER, 80, 90);

    lv_obj_t *lbl_max_sub = lv_label_create(parent);
    lv_label_set_text(lbl_max_sub, "max km/h");
    lv_obj_set_style_text_font(lbl_max_sub, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_max_sub, col_muted, 0);
    lv_obj_set_style_text_align(lbl_max_sub, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_max_sub, LV_ALIGN_CENTER, 80, 110);
}
