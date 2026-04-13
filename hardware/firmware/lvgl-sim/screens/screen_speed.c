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

    /* --- Arc gauge ---
     * 270 deg sweep, open at the bottom. Thicker stroke (18 px) so the
     * indicator stays visible at arm's length on a moving motorbike. */
    lv_obj_t *arc = lv_arc_create(parent);
    lv_obj_set_size(arc, 420, 420);
    lv_arc_set_rotation(arc, 135);
    lv_arc_set_bg_angles(arc, 0, 270);
    lv_arc_set_range(arc, 0, 300);
    lv_arc_set_value(arc, speed_kmh > 300 ? 300 : (int16_t)speed_kmh);
    lv_obj_align(arc, LV_ALIGN_CENTER, 0, 0);

    lv_obj_remove_style(arc, NULL, LV_PART_KNOB);
    lv_obj_clear_flag(arc, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_set_style_arc_color(arc, SCRAM_COLOR_INACTIVE, LV_PART_MAIN);
    lv_obj_set_style_arc_width(arc, 18, LV_PART_MAIN);
    lv_obj_set_style_arc_rounded(arc, true, LV_PART_MAIN);

    lv_obj_set_style_arc_color(arc, col_arc, LV_PART_INDICATOR);
    lv_obj_set_style_arc_width(arc, 18, LV_PART_INDICATOR);
    lv_obj_set_style_arc_rounded(arc, true, LV_PART_INDICATOR);

    /* --- Hero speed digits ---
     * Largest pre-rendered Montserrat is 48 px. Scale ~2.6x via the
     * widget transform so digits read at ~125 px tall on the 466 px
     * display — by far the dominant element on the screen. */
    char speed_buf[8];
    snprintf(speed_buf, sizeof(speed_buf), "%u", (unsigned)speed_kmh);

    lv_obj_t *lbl_speed = lv_label_create(parent);
    lv_label_set_text(lbl_speed, speed_buf);
    lv_obj_set_style_text_font(lbl_speed, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_speed, col_text, 0);
    lv_obj_set_style_text_align(lbl_speed, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_speed, LV_ALIGN_CENTER, 0, -20);
    lv_obj_update_layout(lbl_speed);
    lv_obj_set_style_transform_pivot_x(lbl_speed, lv_obj_get_width(lbl_speed) / 2, 0);
    lv_obj_set_style_transform_pivot_y(lbl_speed, lv_obj_get_height(lbl_speed) / 2, 0);
    lv_obj_set_style_transform_scale(lbl_speed, 660, 0);

    /* --- Unit label (under the digits) --- */
    lv_obj_t *lbl_unit = lv_label_create(parent);
    lv_label_set_text(lbl_unit, "km/h");
    lv_obj_set_style_text_font(lbl_unit, &lv_font_montserrat_36, 0);
    lv_obj_set_style_text_color(lbl_unit, col_muted, 0);
    lv_obj_set_style_text_align(lbl_unit, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_unit, LV_ALIGN_CENTER, 0, 95);

    /* Heading, altitude, temperature removed: irrelevant chrome that
     * stole real estate from the speed reading. The compass and
     * altitude screens already render those values when needed. */
    (void)altitude_m;
    (void)temp_whole;
    (void)heading_deg;
    (void)col_head;
}
