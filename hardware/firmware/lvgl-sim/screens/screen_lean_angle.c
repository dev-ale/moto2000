/*
 * screen_lean_angle.c — lean angle screen with arc gauge
 *                        (matches docs/mockups-extra.html).
 *
 * Layout:
 *   - Title:         "LEAN"          SCRAM_FONT_SMALL, muted gray, top
 *   - Arc gauge:     180 deg sweep, green zones at moderate angles,
 *                    orange/yellow at extremes
 *   - Needle:        lv_line from center-bottom pivot to current angle
 *   - Digital readout: "24°"         SCRAM_FONT_HERO, white, center
 *   - Direction:     "LEFT"/"RIGHT"  SCRAM_FONT_LABEL, green accent
 *   - Max left:      "MAX 38°"       SCRAM_FONT_SMALL, muted gray
 *   - Max right:     "MAX 35°"       SCRAM_FONT_SMALL, muted gray
 *
 * Night mode: red palette for arc and accent.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_lean_angle.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <math.h>
#include <stdio.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define DISPLAY_SIZE 466
#define CENTER_X     (DISPLAY_SIZE / 2)
#define PIVOT_Y      310 /* center-bottom pivot for the needle  */
#define ARC_RADIUS   160 /* radius of the arc gauge             */
#define NEEDLE_LEN   140 /* length from pivot to tip            */

/* ------------------------------------------------------------------ */
/*  Needle via lv_line                                                  */
/* ------------------------------------------------------------------ */

static void create_needle(lv_obj_t *parent, int16_t lean_deg_x10, lv_color_t col)
{
    /* lean_deg_x10: negative = left, positive = right.
     * Map to angle: 0° lean = straight up from pivot (90° in screen coords).
     * Left lean -> needle rotates CCW, right lean -> CW.
     * Angle from vertical in radians. */
    double angle_deg = (double)lean_deg_x10 / 10.0;
    double angle_rad = angle_deg * (M_PI / 180.0);

    int tip_x = CENTER_X + (int)lround(sin(angle_rad) * NEEDLE_LEN);
    int tip_y = PIVOT_Y - (int)lround(cos(angle_rad) * NEEDLE_LEN);

    static lv_point_precise_t needle_pts[2];
    needle_pts[0].x = CENTER_X;
    needle_pts[0].y = PIVOT_Y;
    needle_pts[1].x = tip_x;
    needle_pts[1].y = tip_y;

    lv_obj_t *line = lv_line_create(parent);
    lv_line_set_points(line, needle_pts, 2);
    lv_obj_set_style_line_color(line, col, 0);
    lv_obj_set_style_line_width(line, 4, 0);
    lv_obj_set_style_line_rounded(line, true, 0);
    lv_obj_set_size(line, DISPLAY_SIZE, DISPLAY_SIZE);
    lv_obj_set_pos(line, 0, 0);

    /* Pivot dot */
    lv_obj_t *dot = lv_obj_create(parent);
    lv_obj_set_size(dot, 12, 12);
    lv_obj_set_style_radius(dot, 6, 0);
    lv_obj_set_style_bg_color(dot, col, 0);
    lv_obj_set_style_bg_opa(dot, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(dot, 0, 0);
    lv_obj_clear_flag(dot, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(dot, LV_ALIGN_TOP_LEFT, CENTER_X - 6, PIVOT_Y - 6);
}

/* ------------------------------------------------------------------ */
/*  Arc gauge tick marks via lv_line                                    */
/* ------------------------------------------------------------------ */

/* Draw tick marks around the 180° arc from -90° to +90° lean.
 * Green for moderate (0-30°), orange for extreme (30-90°). */
static void create_arc_ticks(lv_obj_t *parent, lv_color_t col_green, lv_color_t col_orange)
{
    /* Ticks at every 10° from -90 to +90 = 19 ticks. */
    for (int deg = -90; deg <= 90; deg += 10) {
        double angle_rad = (double)deg * (M_PI / 180.0);
        int abs_deg = deg < 0 ? -deg : deg;

        lv_color_t col = (abs_deg <= 30) ? col_green : col_orange;
        bool major = (abs_deg % 30 == 0);
        int tick_outer = ARC_RADIUS;
        int tick_inner = ARC_RADIUS - (major ? 16 : 10);

        int ox = CENTER_X + (int)lround(sin(angle_rad) * tick_outer);
        int oy = PIVOT_Y - (int)lround(cos(angle_rad) * tick_outer);
        int ix = CENTER_X + (int)lround(sin(angle_rad) * tick_inner);
        int iy = PIVOT_Y - (int)lround(cos(angle_rad) * tick_inner);

        static lv_point_precise_t tick_pts[19][2];
        int idx = (deg + 90) / 10;
        tick_pts[idx][0].x = ix;
        tick_pts[idx][0].y = iy;
        tick_pts[idx][1].x = ox;
        tick_pts[idx][1].y = oy;

        lv_obj_t *line = lv_line_create(parent);
        lv_line_set_points(line, tick_pts[idx], 2);
        lv_obj_set_style_line_color(line, col, 0);
        lv_obj_set_style_line_width(line, major ? 3 : 2, 0);
        lv_obj_set_size(line, DISPLAY_SIZE, DISPLAY_SIZE);
        lv_obj_set_pos(line, 0, 0);
    }
}

/* ------------------------------------------------------------------ */
/*  Screen layout                                                      */
/* ------------------------------------------------------------------ */

void screen_lean_angle_create(lv_obj_t *parent, const ble_lean_angle_data_t *data, uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_WHITE;
    lv_color_t col_muted = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_green = night ? SCRAM_COLOR_RED : SCRAM_COLOR_GREEN;
    lv_color_t col_orange = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_ORANGE;
    lv_color_t col_needle = night ? SCRAM_COLOR_RED : SCRAM_COLOR_WHITE;

    (void)flags;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* Derived values. */
    int16_t lean_deg = data->current_lean_deg_x10 / 10;
    int16_t abs_lean = lean_deg < 0 ? -lean_deg : lean_deg;
    uint16_t max_left_deg = data->max_left_lean_deg_x10 / 10;
    uint16_t max_right_deg = data->max_right_lean_deg_x10 / 10;

    /* --- Title --- */
    lv_obj_t *lbl_title = lv_label_create(parent);
    lv_label_set_text(lbl_title, "LEAN");
    lv_obj_set_style_text_font(lbl_title, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_title, col_muted, 0);
    lv_obj_set_style_text_align(lbl_title, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_title, LV_ALIGN_TOP_MID, 0, 50);

    /* --- Arc gauge ticks --- */
    create_arc_ticks(parent, col_green, col_orange);

    /* --- Needle --- */
    create_needle(parent, data->current_lean_deg_x10, col_needle);

    /* --- Digital readout --- */
    char readout_buf[16];
    snprintf(readout_buf, sizeof(readout_buf), "%d\xC2\xB0", (int)abs_lean);

    lv_obj_t *lbl_readout = lv_label_create(parent);
    lv_label_set_text(lbl_readout, readout_buf);
    lv_obj_set_style_text_font(lbl_readout, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_readout, col_text, 0);
    lv_obj_set_style_text_align(lbl_readout, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_readout, LV_ALIGN_CENTER, 0, 30);

    /* --- Direction label --- */
    const char *direction;
    if (lean_deg < 0) {
        direction = "LEFT";
    } else if (lean_deg > 0) {
        direction = "RIGHT";
    } else {
        direction = "CENTER";
    }

    lv_obj_t *lbl_dir = lv_label_create(parent);
    lv_label_set_text(lbl_dir, direction);
    lv_obj_set_style_text_font(lbl_dir, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_dir, col_green, 0);
    lv_obj_set_style_text_align(lbl_dir, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_dir, LV_ALIGN_CENTER, 0, 75);

    /* --- Max left indicator --- */
    char max_left_buf[24];
    snprintf(max_left_buf, sizeof(max_left_buf), "MAX %u\xC2\xB0", (unsigned)max_left_deg);

    lv_obj_t *lbl_max_left = lv_label_create(parent);
    lv_label_set_text(lbl_max_left, max_left_buf);
    lv_obj_set_style_text_font(lbl_max_left, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_max_left, col_muted, 0);
    lv_obj_align(lbl_max_left, LV_ALIGN_CENTER, -100, 120);

    /* --- Max right indicator --- */
    char max_right_buf[24];
    snprintf(max_right_buf, sizeof(max_right_buf), "MAX %u\xC2\xB0", (unsigned)max_right_deg);

    lv_obj_t *lbl_max_right = lv_label_create(parent);
    lv_label_set_text(lbl_max_right, max_right_buf);
    lv_obj_set_style_text_font(lbl_max_right, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_max_right, col_muted, 0);
    lv_obj_align(lbl_max_right, LV_ALIGN_CENTER, 100, 120);
}
