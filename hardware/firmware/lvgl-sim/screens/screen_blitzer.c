/*
 * screen_blitzer.c — blitzer/radar warning screen with speed limit and distance
 *                     (matches docs/mockups-extra.html).
 *
 * Layout:
 *   - Warning text:      "CAMERA AHEAD"    SCRAM_FONT_SMALL, red, top
 *   - Speed limit circle: European-style red-bordered circle with limit number
 *   - Concentric radar rings: 3 circles, red with decreasing opacity
 *   - Hero distance:     "380m"            SCRAM_FONT_HERO, white, center
 *   - Camera type:       "FIXED CAMERA"    SCRAM_FONT_SMALL, muted gray
 *   - Speed comparison pill: rounded rect, red if speeding, muted if not
 *
 * This is an alert overlay with the ALERT flag set. Red-themed by default,
 * so night mode just dims slightly.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_blitzer.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <stdio.h>

/* ------------------------------------------------------------------ */
/*  Camera type text mapping                                            */
/* ------------------------------------------------------------------ */

static const char *camera_type_text(ble_camera_type_t type)
{
    switch (type) {
    case BLE_CAMERA_TYPE_FIXED:
        return "FIXED CAMERA";
    case BLE_CAMERA_TYPE_MOBILE:
        return "MOBILE";
    case BLE_CAMERA_TYPE_RED_LIGHT:
        return "RED LIGHT";
    case BLE_CAMERA_TYPE_SECTION:
        return "SECTION";
    case BLE_CAMERA_TYPE_UNKNOWN:
        return "UNKNOWN";
    }
    return "UNKNOWN";
}

/* ------------------------------------------------------------------ */
/*  Screen layout                                                      */
/* ------------------------------------------------------------------ */

void screen_blitzer_create(lv_obj_t *parent, const ble_blitzer_data_t *data, uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_WHITE;
    lv_color_t col_muted = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_red = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_RED;

    (void)flags;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* Derived values. */
    uint16_t current_kmh = data->current_speed_kmh_x10 / 10;
    bool has_limit = (data->speed_limit_kmh != 0xFFFF);
    bool is_speeding = has_limit && (current_kmh > data->speed_limit_kmh);

    /* --- Warning text --- */
    lv_obj_t *lbl_warn = lv_label_create(parent);
    lv_label_set_text(lbl_warn, "CAMERA AHEAD");
    lv_obj_set_style_text_font(lbl_warn, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_warn, col_red, 0);
    lv_obj_set_style_text_align(lbl_warn, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_warn, LV_ALIGN_TOP_MID, 0, 55);

    /* --- Speed limit circle (European road-sign style) --- */
    /* Outer red ring. */
    lv_obj_t *sign_outer = lv_obj_create(parent);
    lv_obj_set_size(sign_outer, 80, 80);
    lv_obj_set_style_radius(sign_outer, 40, 0);
    lv_obj_set_style_bg_color(sign_outer, col_red, 0);
    lv_obj_set_style_bg_opa(sign_outer, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(sign_outer, 0, 0);
    lv_obj_set_style_pad_all(sign_outer, 0, 0);
    lv_obj_clear_flag(sign_outer, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(sign_outer, LV_ALIGN_CENTER, 0, -80);

    /* Inner white circle. */
    lv_obj_t *sign_inner = lv_obj_create(sign_outer);
    lv_obj_set_size(sign_inner, 64, 64);
    lv_obj_set_style_radius(sign_inner, 32, 0);
    lv_obj_set_style_bg_color(sign_inner, SCRAM_COLOR_WHITE, 0);
    lv_obj_set_style_bg_opa(sign_inner, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(sign_inner, 0, 0);
    lv_obj_set_style_pad_all(sign_inner, 0, 0);
    lv_obj_clear_flag(sign_inner, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_center(sign_inner);

    /* Speed limit number. */
    char limit_buf[8];
    if (has_limit) {
        snprintf(limit_buf, sizeof(limit_buf), "%u", (unsigned)data->speed_limit_kmh);
    } else {
        snprintf(limit_buf, sizeof(limit_buf), "--");
    }

    lv_obj_t *lbl_limit = lv_label_create(sign_inner);
    lv_label_set_text(lbl_limit, limit_buf);
    lv_obj_set_style_text_font(lbl_limit, SCRAM_FONT_VALUE, 0);
    lv_obj_set_style_text_color(lbl_limit, lv_color_hex(0x000000), 0);
    lv_obj_set_style_text_align(lbl_limit, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_center(lbl_limit);

    /* --- Concentric radar rings --- */
    /* Ring 1 (outermost, lowest opacity). */
    lv_obj_t *ring1 = lv_obj_create(parent);
    lv_obj_set_size(ring1, 300, 300);
    lv_obj_set_style_radius(ring1, 150, 0);
    lv_obj_set_style_bg_opa(ring1, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_color(ring1, col_red, 0);
    lv_obj_set_style_border_width(ring1, 1, 0);
    lv_obj_set_style_border_opa(ring1, LV_OPA_20, 0);
    lv_obj_clear_flag(ring1, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(ring1, LV_ALIGN_CENTER, 0, 10);

    /* Ring 2 (middle). */
    lv_obj_t *ring2 = lv_obj_create(parent);
    lv_obj_set_size(ring2, 220, 220);
    lv_obj_set_style_radius(ring2, 110, 0);
    lv_obj_set_style_bg_opa(ring2, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_color(ring2, col_red, 0);
    lv_obj_set_style_border_width(ring2, 1, 0);
    lv_obj_set_style_border_opa(ring2, LV_OPA_40, 0);
    lv_obj_clear_flag(ring2, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(ring2, LV_ALIGN_CENTER, 0, 10);

    /* Ring 3 (innermost, highest opacity). */
    lv_obj_t *ring3 = lv_obj_create(parent);
    lv_obj_set_size(ring3, 140, 140);
    lv_obj_set_style_radius(ring3, 70, 0);
    lv_obj_set_style_bg_opa(ring3, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_color(ring3, col_red, 0);
    lv_obj_set_style_border_width(ring3, 1, 0);
    lv_obj_set_style_border_opa(ring3, LV_OPA_60, 0);
    lv_obj_clear_flag(ring3, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(ring3, LV_ALIGN_CENTER, 0, 10);

    /* --- Hero distance --- */
    char dist_buf[16];
    if (data->distance_meters >= 1000) {
        uint16_t km = data->distance_meters / 1000;
        uint16_t hm = (data->distance_meters % 1000) / 100;
        snprintf(dist_buf, sizeof(dist_buf), "%u.%ukm", (unsigned)km, (unsigned)hm);
    } else {
        snprintf(dist_buf, sizeof(dist_buf), "%um", (unsigned)data->distance_meters);
    }

    lv_obj_t *lbl_dist = lv_label_create(parent);
    lv_label_set_text(lbl_dist, dist_buf);
    lv_obj_set_style_text_font(lbl_dist, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_dist, col_text, 0);
    lv_obj_set_style_text_align(lbl_dist, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_dist, LV_ALIGN_CENTER, 0, 10);

    /* --- Camera type --- */
    lv_obj_t *lbl_type = lv_label_create(parent);
    lv_label_set_text(lbl_type, camera_type_text(data->camera_type));
    lv_obj_set_style_text_font(lbl_type, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_type, col_muted, 0);
    lv_obj_set_style_text_align(lbl_type, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_type, LV_ALIGN_CENTER, 0, 50);

    /* --- Speed comparison pill --- */
    /* Show "67 > 50" style. Red bg if speeding, dark bg otherwise. */
    char speed_buf[32];
    if (has_limit) {
        snprintf(speed_buf, sizeof(speed_buf), "%u > %u", (unsigned)current_kmh,
                 (unsigned)data->speed_limit_kmh);
    } else {
        snprintf(speed_buf, sizeof(speed_buf), "%u km/h", (unsigned)current_kmh);
    }

    lv_obj_t *pill = lv_obj_create(parent);
    lv_obj_set_size(pill, 160, 36);
    lv_obj_set_style_radius(pill, 18, 0);
    lv_obj_set_style_bg_color(pill, is_speeding ? col_red : SCRAM_COLOR_INACTIVE, 0);
    lv_obj_set_style_bg_opa(pill, is_speeding ? LV_OPA_80 : LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(pill, 0, 0);
    lv_obj_clear_flag(pill, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(pill, LV_ALIGN_CENTER, 0, 90);

    lv_obj_t *lbl_speed = lv_label_create(pill);
    lv_label_set_text(lbl_speed, speed_buf);
    lv_obj_set_style_text_font(lbl_speed, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_speed, col_text, 0);
    lv_obj_set_style_text_align(lbl_speed, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_center(lbl_speed);
}
