/*
 * screen_speed.c — speed + heading screen (matches docs/mockups.html).
 *
 * Layout (from the SVG mockup "Speed + heading"):
 *   - Arc gauge ring:   270 deg sweep, 0-300 km/h, green active / dark inactive
 *   - Hero digits:      "67"           SCRAM_FONT_HERO,  white, center
 *   - Unit:             "km/h"         SCRAM_FONT_LABEL, muted gray
 *   - Heading:          "NE 042"       SCRAM_FONT_VALUE, accent blue
 *   - Altitude (left):  "612m"         SCRAM_FONT_SMALL, muted gray
 *   - Temperature (right): "18 C"      SCRAM_FONT_SMALL, muted gray
 *
 * Night mode: arc active colour switches to red; heading becomes muted red.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_speed.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <stdio.h>

/* ------------------------------------------------------------------ */
/*  Cardinal direction helper                                          */
/* ------------------------------------------------------------------ */

static const char *heading_to_cardinal(uint16_t heading_deg_x10)
{
    uint16_t deg = heading_deg_x10 / 10;
    if (deg >= 338 || deg < 23)
        return "N";
    if (deg < 68)
        return "NE";
    if (deg < 113)
        return "E";
    if (deg < 158)
        return "SE";
    if (deg < 203)
        return "S";
    if (deg < 248)
        return "SW";
    if (deg < 293)
        return "W";
    return "NW";
}

/* ------------------------------------------------------------------ */
/*  Screen layout                                                      */
/* ------------------------------------------------------------------ */

void screen_speed_create(lv_obj_t *parent, const ble_speed_heading_data_t *data, uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_WHITE;
    lv_color_t col_muted = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_arc = night ? SCRAM_COLOR_RED : SCRAM_COLOR_GREEN;
    lv_color_t col_head = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_BLUE;

    (void)flags;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* Derived values. */
    uint16_t speed_kmh = data->speed_kmh_x10 / 10;
    uint16_t heading_deg = data->heading_deg_x10 / 10;
    int16_t altitude_m = data->altitude_m;
    int16_t temp_whole = data->temperature_celsius_x10 / 10;

    /* --- Arc gauge --- */
    /* The arc spans 270 deg (like a car speedometer), open at the bottom.
     * LVGL arc angles: 0 = 3-o'clock, CW.
     * We want the arc to start at 135 deg (bottom-left) and end at 45 deg
     * (bottom-right), sweeping 270 deg CW through top.
     * bg_angles = full background, indicator = filled portion. */
    lv_obj_t *arc = lv_arc_create(parent);
    lv_obj_set_size(arc, 330, 330);
    lv_arc_set_rotation(arc, 135);
    lv_arc_set_bg_angles(arc, 0, 270);
    lv_arc_set_range(arc, 0, 300);
    lv_arc_set_value(arc, speed_kmh > 300 ? 300 : (int16_t)speed_kmh);
    lv_obj_align(arc, LV_ALIGN_CENTER, 0, -10);

    /* Remove the knob (no interactive handle). */
    lv_obj_remove_style(arc, NULL, LV_PART_KNOB);
    lv_obj_clear_flag(arc, LV_OBJ_FLAG_CLICKABLE);

    /* Background (inactive) arc. */
    lv_obj_set_style_arc_color(arc, SCRAM_COLOR_INACTIVE, LV_PART_MAIN);
    lv_obj_set_style_arc_width(arc, 10, LV_PART_MAIN);
    lv_obj_set_style_arc_rounded(arc, true, LV_PART_MAIN);

    /* Indicator (active) arc. */
    lv_obj_set_style_arc_color(arc, col_arc, LV_PART_INDICATOR);
    lv_obj_set_style_arc_width(arc, 10, LV_PART_INDICATOR);
    lv_obj_set_style_arc_rounded(arc, true, LV_PART_INDICATOR);

    /* --- Hero speed digits --- */
    char speed_buf[8];
    snprintf(speed_buf, sizeof(speed_buf), "%u", (unsigned)speed_kmh);

    lv_obj_t *lbl_speed = lv_label_create(parent);
    lv_label_set_text(lbl_speed, speed_buf);
    lv_obj_set_style_text_font(lbl_speed, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_speed, col_text, 0);
    lv_obj_set_style_text_align(lbl_speed, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_speed, LV_ALIGN_CENTER, 0, -40);

    /* --- Unit label --- */
    lv_obj_t *lbl_unit = lv_label_create(parent);
    lv_label_set_text(lbl_unit, "km/h");
    lv_obj_set_style_text_font(lbl_unit, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_unit, col_muted, 0);
    lv_obj_set_style_text_align(lbl_unit, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_unit, LV_ALIGN_CENTER, 0, 0);

    /* --- Heading with cardinal direction --- */
    char heading_buf[16];
    snprintf(heading_buf, sizeof(heading_buf), "%s %03u\xC2\xB0",
             heading_to_cardinal(data->heading_deg_x10), (unsigned)heading_deg);

    lv_obj_t *lbl_heading = lv_label_create(parent);
    lv_label_set_text(lbl_heading, heading_buf);
    lv_obj_set_style_text_font(lbl_heading, SCRAM_FONT_VALUE, 0);
    lv_obj_set_style_text_color(lbl_heading, col_head, 0);
    lv_obj_set_style_text_align(lbl_heading, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_heading, LV_ALIGN_CENTER, 0, 50);

    /* --- Altitude (bottom-left) --- */
    char alt_buf[16];
    snprintf(alt_buf, sizeof(alt_buf), "%dm", (int)altitude_m);

    lv_obj_t *lbl_alt = lv_label_create(parent);
    lv_label_set_text(lbl_alt, alt_buf);
    lv_obj_set_style_text_font(lbl_alt, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_alt, col_muted, 0);
    lv_obj_align(lbl_alt, LV_ALIGN_CENTER, -70, 110);

    /* Altitude dot. */
    lv_obj_t *dot_alt = lv_obj_create(parent);
    lv_obj_set_size(dot_alt, 6, 6);
    lv_obj_set_style_radius(dot_alt, 3, 0);
    lv_obj_set_style_bg_color(dot_alt, col_muted, 0);
    lv_obj_set_style_bg_opa(dot_alt, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(dot_alt, 0, 0);
    lv_obj_clear_flag(dot_alt, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(dot_alt, LV_ALIGN_CENTER, -70, 96);

    /* --- Temperature (bottom-right) --- */
    char temp_buf[16];
    snprintf(temp_buf, sizeof(temp_buf),
             "%d\xC2\xB0"
             "C",
             (int)temp_whole);

    lv_obj_t *lbl_temp = lv_label_create(parent);
    lv_label_set_text(lbl_temp, temp_buf);
    lv_obj_set_style_text_font(lbl_temp, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_temp, col_muted, 0);
    lv_obj_align(lbl_temp, LV_ALIGN_CENTER, 70, 110);

    /* Temperature dot. */
    lv_obj_t *dot_temp = lv_obj_create(parent);
    lv_obj_set_size(dot_temp, 6, 6);
    lv_obj_set_style_radius(dot_temp, 3, 0);
    lv_obj_set_style_bg_color(dot_temp, col_muted, 0);
    lv_obj_set_style_bg_opa(dot_temp, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(dot_temp, 0, 0);
    lv_obj_clear_flag(dot_temp, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(dot_temp, LV_ALIGN_CENTER, 70, 96);
}
