/*
 * screen_altitude.c — altitude profile screen with line chart
 *                      (matches docs/mockups-extra.html).
 *
 * Layout:
 *   - Title:        "ALTITUDE"           SCRAM_FONT_SMALL, muted gray, top
 *   - Hero altitude: "1248M"             SCRAM_FONT_HERO, white
 *   - Status line:   "+86M TO PEAK"      SCRAM_FONT_LABEL, green accent
 *   - Line chart:    elevation profile drawn via lv_line polylines
 *                    (green = traveled, gray = future, dot = current pos)
 *   - X-axis labels: distance markers    SCRAM_FONT_SMALL, muted gray
 *   - Ascent total:  "^ 1420M"           SCRAM_FONT_SMALL, orange
 *   - Descent total: "v 890M"            SCRAM_FONT_SMALL, blue
 *
 * The chart is drawn with lv_line rather than lv_chart because
 * LV_USE_CHART is not enabled in lv_conf.h to keep the ESP-IDF
 * binary size minimal.
 *
 * Night mode: red palette, red chart line.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_altitude.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <stdio.h>

/* ------------------------------------------------------------------ */
/*  Chart area constants                                                */
/* ------------------------------------------------------------------ */

#define DISPLAY_SIZE  466
#define CHART_LEFT    80
#define CHART_RIGHT   386
#define CHART_TOP     220
#define CHART_BOTTOM  340
#define CHART_W       (CHART_RIGHT - CHART_LEFT)
#define CHART_H       (CHART_BOTTOM - CHART_TOP)

/* ------------------------------------------------------------------ */
/*  Helpers                                                             */
/* ------------------------------------------------------------------ */

/* Map an altitude value to a Y pixel within the chart area. */
static int alt_to_y(int16_t alt, int16_t min_alt, int16_t max_alt)
{
    if (max_alt == min_alt) return CHART_TOP + CHART_H / 2;
    int range = max_alt - min_alt;
    int offset = alt - min_alt;
    /* Invert: higher altitude = lower Y. */
    return CHART_BOTTOM - (int)((long)offset * CHART_H / range);
}

/* Map a sample index to an X pixel. */
static int idx_to_x(int idx, int count)
{
    if (count <= 1) return CHART_LEFT + CHART_W / 2;
    return CHART_LEFT + (int)((long)idx * CHART_W / (count - 1));
}

/* Find the peak (max altitude) among remaining samples after current position.
 * Returns the altitude delta to the peak, or 0 if we're at or past it. */
static int16_t meters_to_peak(const ble_altitude_profile_data_t *data)
{
    if (data->sample_count == 0) return 0;
    int16_t peak = data->current_altitude_m;
    for (uint8_t i = 0; i < data->sample_count; i++) {
        if (data->profile[i] > peak) {
            peak = data->profile[i];
        }
    }
    int16_t delta = peak - data->current_altitude_m;
    return delta > 0 ? delta : 0;
}

/* ------------------------------------------------------------------ */
/*  Profile line drawing                                                */
/* ------------------------------------------------------------------ */

/* We split the profile into two polylines:
 * - "traveled" portion (samples 0..current_idx) in green/red
 * - "future" portion (samples current_idx..end) in gray
 *
 * The current position is estimated as the sample whose altitude is
 * closest to current_altitude_m (searching from the end backward to
 * handle plateaus). If sample_count == 0, we skip the chart.
 */
static void draw_profile(lv_obj_t *parent,
                         const ble_altitude_profile_data_t *data,
                         lv_color_t col_traveled, lv_color_t col_future,
                         lv_color_t col_dot)
{
    uint8_t n = data->sample_count;
    if (n == 0) return;
    if (n > BLE_ALTITUDE_MAX_SAMPLES) n = BLE_ALTITUDE_MAX_SAMPLES;

    /* Find min/max altitude for scaling. */
    int16_t min_alt = data->profile[0];
    int16_t max_alt = data->profile[0];
    for (uint8_t i = 1; i < n; i++) {
        if (data->profile[i] < min_alt) min_alt = data->profile[i];
        if (data->profile[i] > max_alt) max_alt = data->profile[i];
    }
    /* Ensure current altitude is in range. */
    if (data->current_altitude_m < min_alt) min_alt = data->current_altitude_m;
    if (data->current_altitude_m > max_alt) max_alt = data->current_altitude_m;
    /* Add a small margin to avoid flat-line rendering. */
    if (max_alt - min_alt < 20) {
        min_alt -= 10;
        max_alt += 10;
    }

    /* Find current position index: closest altitude match. */
    int cur_idx = 0;
    int best_diff = 32767;
    for (uint8_t i = 0; i < n; i++) {
        int diff = data->profile[i] - data->current_altitude_m;
        if (diff < 0) diff = -diff;
        if (diff <= best_diff) {
            best_diff = diff;
            cur_idx = i;
        }
    }

    /* Build point arrays. We use static storage since LVGL keeps
     * references to them. */
    static lv_point_precise_t pts_traveled[BLE_ALTITUDE_MAX_SAMPLES];
    static lv_point_precise_t pts_future[BLE_ALTITUDE_MAX_SAMPLES];

    /* Traveled polyline: 0..cur_idx (inclusive). */
    int traveled_count = cur_idx + 1;
    for (int i = 0; i < traveled_count; i++) {
        pts_traveled[i].x = idx_to_x(i, n);
        pts_traveled[i].y = alt_to_y(data->profile[i], min_alt, max_alt);
    }

    if (traveled_count >= 2) {
        lv_obj_t *line_t = lv_line_create(parent);
        lv_line_set_points(line_t, pts_traveled, (uint16_t)traveled_count);
        lv_obj_set_style_line_color(line_t, col_traveled, 0);
        lv_obj_set_style_line_width(line_t, 3, 0);
        lv_obj_set_style_line_rounded(line_t, true, 0);
        lv_obj_set_size(line_t, DISPLAY_SIZE, DISPLAY_SIZE);
        lv_obj_set_pos(line_t, 0, 0);
    }

    /* Future polyline: cur_idx..end. */
    int future_count = n - cur_idx;
    for (int i = 0; i < future_count; i++) {
        int si = cur_idx + i;
        pts_future[i].x = idx_to_x(si, n);
        pts_future[i].y = alt_to_y(data->profile[si], min_alt, max_alt);
    }

    if (future_count >= 2) {
        lv_obj_t *line_f = lv_line_create(parent);
        lv_line_set_points(line_f, pts_future, (uint16_t)future_count);
        lv_obj_set_style_line_color(line_f, col_future, 0);
        lv_obj_set_style_line_width(line_f, 2, 0);
        lv_obj_set_style_line_rounded(line_f, true, 0);
        lv_obj_set_size(line_f, DISPLAY_SIZE, DISPLAY_SIZE);
        lv_obj_set_pos(line_f, 0, 0);
    }

    /* Current position dot. */
    int dot_x = idx_to_x(cur_idx, n);
    int dot_y = alt_to_y(data->profile[cur_idx], min_alt, max_alt);

    lv_obj_t *dot = lv_obj_create(parent);
    lv_obj_set_size(dot, 10, 10);
    lv_obj_set_style_radius(dot, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(dot, col_dot, 0);
    lv_obj_set_style_bg_opa(dot, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(dot, 0, 0);
    lv_obj_clear_flag(dot, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(dot, LV_ALIGN_TOP_LEFT, dot_x - 5, dot_y - 5);

    /* Dashed vertical line at current position (drawn as short segments). */
    int dash_len = 6;
    int gap_len = 4;
    int y = CHART_TOP;
    int dash_idx = 0;
    static lv_point_precise_t dash_pts[30][2]; /* max ~30 dashes */
    while (y < CHART_BOTTOM && dash_idx < 30) {
        int y_end = y + dash_len;
        if (y_end > CHART_BOTTOM) y_end = CHART_BOTTOM;

        dash_pts[dash_idx][0].x = dot_x;
        dash_pts[dash_idx][0].y = y;
        dash_pts[dash_idx][1].x = dot_x;
        dash_pts[dash_idx][1].y = y_end;

        lv_obj_t *dl = lv_line_create(parent);
        lv_line_set_points(dl, dash_pts[dash_idx], 2);
        lv_obj_set_style_line_color(dl, col_dot, 0);
        lv_obj_set_style_line_width(dl, 1, 0);
        lv_obj_set_style_line_opa(dl, LV_OPA_50, 0);
        lv_obj_set_size(dl, DISPLAY_SIZE, DISPLAY_SIZE);
        lv_obj_set_pos(dl, 0, 0);

        y = y_end + gap_len;
        dash_idx++;
    }
}

/* ------------------------------------------------------------------ */
/*  Screen layout                                                      */
/* ------------------------------------------------------------------ */

void screen_altitude_create(lv_obj_t *parent,
                            const ble_altitude_profile_data_t *data,
                            uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text     = night ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_WHITE;
    lv_color_t col_muted    = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_green    = night ? SCRAM_COLOR_RED         : SCRAM_COLOR_GREEN;
    lv_color_t col_orange   = night ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_ORANGE;
    lv_color_t col_blue     = night ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_BLUE;
    lv_color_t col_future   = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_INACTIVE;

    (void)flags;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* --- Title --- */
    lv_obj_t *lbl_title = lv_label_create(parent);
    lv_label_set_text(lbl_title, "ALTITUDE");
    lv_obj_set_style_text_font(lbl_title, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_title, col_muted, 0);
    lv_obj_set_style_text_align(lbl_title, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_title, LV_ALIGN_TOP_MID, 0, 60);

    /* --- Hero altitude --- */
    char hero_buf[16];
    snprintf(hero_buf, sizeof(hero_buf), "%dM",
             (int)data->current_altitude_m);

    lv_obj_t *lbl_hero = lv_label_create(parent);
    lv_label_set_text(lbl_hero, hero_buf);
    lv_obj_set_style_text_font(lbl_hero, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_hero, col_text, 0);
    lv_obj_set_style_text_align(lbl_hero, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_hero, LV_ALIGN_TOP_MID, 0, 90);

    /* --- Status line --- */
    int16_t to_peak = meters_to_peak(data);
    char status_buf[32];
    if (to_peak > 0) {
        snprintf(status_buf, sizeof(status_buf), "+%dM TO PEAK", (int)to_peak);
    } else {
        snprintf(status_buf, sizeof(status_buf), "AT PEAK");
    }

    lv_obj_t *lbl_status = lv_label_create(parent);
    lv_label_set_text(lbl_status, status_buf);
    lv_obj_set_style_text_font(lbl_status, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_status, col_green, 0);
    lv_obj_set_style_text_align(lbl_status, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_status, LV_ALIGN_TOP_MID, 0, 155);

    /* --- Elevation profile chart --- */
    draw_profile(parent, data, col_green, col_future, col_green);

    /* --- X-axis labels (start, mid, end as sample indices) --- */
    if (data->sample_count > 0) {
        lv_obj_t *lbl_x0 = lv_label_create(parent);
        lv_label_set_text(lbl_x0, "0");
        lv_obj_set_style_text_font(lbl_x0, SCRAM_FONT_SMALL, 0);
        lv_obj_set_style_text_color(lbl_x0, col_muted, 0);
        lv_obj_align(lbl_x0, LV_ALIGN_TOP_LEFT, CHART_LEFT, CHART_BOTTOM + 4);

        if (data->sample_count > 2) {
            char mid_buf[8];
            snprintf(mid_buf, sizeof(mid_buf), "%u",
                     (unsigned)(data->sample_count / 2));
            lv_obj_t *lbl_xm = lv_label_create(parent);
            lv_label_set_text(lbl_xm, mid_buf);
            lv_obj_set_style_text_font(lbl_xm, SCRAM_FONT_SMALL, 0);
            lv_obj_set_style_text_color(lbl_xm, col_muted, 0);
            lv_obj_align(lbl_xm, LV_ALIGN_TOP_MID, 0, CHART_BOTTOM + 4);
        }

        char end_buf[8];
        snprintf(end_buf, sizeof(end_buf), "%u",
                 (unsigned)(data->sample_count - 1));
        lv_obj_t *lbl_xe = lv_label_create(parent);
        lv_label_set_text(lbl_xe, end_buf);
        lv_obj_set_style_text_font(lbl_xe, SCRAM_FONT_SMALL, 0);
        lv_obj_set_style_text_color(lbl_xe, col_muted, 0);
        lv_obj_align(lbl_xe, LV_ALIGN_TOP_LEFT, CHART_RIGHT - 16, CHART_BOTTOM + 4);
    }

    /* --- Ascent total (bottom left) --- */
    char asc_buf[16];
    snprintf(asc_buf, sizeof(asc_buf), "\xE2\x86\x91 %uM",
             (unsigned)data->total_ascent_m);

    lv_obj_t *lbl_asc = lv_label_create(parent);
    lv_label_set_text(lbl_asc, asc_buf);
    lv_obj_set_style_text_font(lbl_asc, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_asc, col_orange, 0);
    lv_obj_align(lbl_asc, LV_ALIGN_CENTER, -70, 140);

    /* --- Descent total (bottom right) --- */
    char desc_buf[16];
    snprintf(desc_buf, sizeof(desc_buf), "\xE2\x86\x93 %uM",
             (unsigned)data->total_descent_m);

    lv_obj_t *lbl_desc = lv_label_create(parent);
    lv_label_set_text(lbl_desc, desc_buf);
    lv_obj_set_style_text_font(lbl_desc, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_desc, col_blue, 0);
    lv_obj_align(lbl_desc, LV_ALIGN_CENTER, 70, 140);
}
