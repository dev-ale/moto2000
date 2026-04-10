/*
 * screen_fuel.c — fuel estimate screen with tank gauge
 *                  (matches docs/mockups-extra.html).
 *
 * Layout:
 *   - Title:       "FUEL"             SCRAM_FONT_SMALL, muted gray, top
 *   - Tank icon:   rounded rect with orange fill rising from bottom,
 *                  small nozzle rectangle on top-right
 *   - Percentage:  "52%"              SCRAM_FONT_VALUE, dark on orange fill
 *   - Range:       "148km"            SCRAM_FONT_HERO, white
 *   - Range label: "Range"            SCRAM_FONT_SMALL, muted gray
 *   - Divider line
 *   - Consumption: "3.2L /100km"      orange + muted gray, left
 *   - Remaining:   "7.8L in tank"     blue + muted gray, right
 *
 * Unknown values (0xFFFF): show "--".
 * Night mode: red palette, fill becomes red.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_fuel.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <stdio.h>

/* ------------------------------------------------------------------ */
/*  Screen layout                                                      */
/* ------------------------------------------------------------------ */

void screen_fuel_create(lv_obj_t *parent,
                        const ble_fuel_data_t *data,
                        uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text   = night ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_WHITE;
    lv_color_t col_muted  = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_fill   = night ? SCRAM_COLOR_RED         : SCRAM_COLOR_ORANGE;
    lv_color_t col_blue   = night ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_BLUE;
    lv_color_t col_dark   = night ? lv_color_hex(0x110000)  : lv_color_hex(0x1A1A1A);

    (void)flags;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* --- Title --- */
    lv_obj_t *lbl_title = lv_label_create(parent);
    lv_label_set_text(lbl_title, "FUEL");
    lv_obj_set_style_text_font(lbl_title, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_title, col_muted, 0);
    lv_obj_set_style_text_align(lbl_title, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_title, LV_ALIGN_TOP_MID, 0, 60);

    /* --- Tank icon --- */
    /* Tank body: rounded rectangle outline. */
    int tank_x = 183;   /* center x - half width */
    int tank_y = 85;
    int tank_w = 100;
    int tank_h = 120;

    lv_obj_t *tank_body = lv_obj_create(parent);
    lv_obj_set_size(tank_body, tank_w, tank_h);
    lv_obj_set_style_radius(tank_body, 10, 0);
    lv_obj_set_style_bg_color(tank_body, col_dark, 0);
    lv_obj_set_style_bg_opa(tank_body, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(tank_body, col_muted, 0);
    lv_obj_set_style_border_width(tank_body, 2, 0);
    lv_obj_set_style_border_opa(tank_body, LV_OPA_60, 0);
    lv_obj_clear_flag(tank_body, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_pad_all(tank_body, 0, 0);
    lv_obj_align(tank_body, LV_ALIGN_TOP_LEFT, tank_x, tank_y);

    /* Tank fill: rises from bottom proportional to tank_percent. */
    uint8_t pct = data->tank_percent;
    if (pct > 100) pct = 100;
    int fill_h = (int)((tank_h - 4) * pct) / 100; /* -4 for border spacing */

    if (fill_h > 0) {
        lv_obj_t *tank_fill = lv_obj_create(tank_body);
        lv_obj_set_size(tank_fill, tank_w - 4, fill_h);
        lv_obj_set_style_radius(tank_fill, 8, 0);
        lv_obj_set_style_bg_color(tank_fill, col_fill, 0);
        lv_obj_set_style_bg_opa(tank_fill, LV_OPA_COVER, 0);
        lv_obj_set_style_border_width(tank_fill, 0, 0);
        lv_obj_clear_flag(tank_fill, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_align(tank_fill, LV_ALIGN_BOTTOM_MID, 0, 0);
    }

    /* Nozzle: small rectangle on top-right of tank. */
    lv_obj_t *nozzle = lv_obj_create(parent);
    lv_obj_set_size(nozzle, 16, 10);
    lv_obj_set_style_radius(nozzle, 3, 0);
    lv_obj_set_style_bg_color(nozzle, col_muted, 0);
    lv_obj_set_style_bg_opa(nozzle, LV_OPA_60, 0);
    lv_obj_set_style_border_width(nozzle, 0, 0);
    lv_obj_clear_flag(nozzle, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(nozzle, LV_ALIGN_TOP_LEFT, tank_x + tank_w - 24, tank_y - 8);

    /* --- Percentage overlaid on tank --- */
    char pct_buf[8];
    snprintf(pct_buf, sizeof(pct_buf), "%u%%", (unsigned)pct);

    lv_obj_t *lbl_pct = lv_label_create(parent);
    lv_label_set_text(lbl_pct, pct_buf);
    lv_obj_set_style_text_font(lbl_pct, SCRAM_FONT_VALUE, 0);
    lv_obj_set_style_text_color(lbl_pct,
        night ? SCRAM_COLOR_NIGHT_TEXT : lv_color_hex(0x1A1A1A), 0);
    lv_obj_set_style_text_align(lbl_pct, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_pct, LV_ALIGN_TOP_LEFT,
                 tank_x + tank_w / 2 - 20, tank_y + tank_h / 2 - 12);

    /* --- Hero range --- */
    char range_buf[16];
    if (data->estimated_range_km == 0xFFFF) {
        snprintf(range_buf, sizeof(range_buf), "--");
    } else {
        snprintf(range_buf, sizeof(range_buf), "%ukm",
                 (unsigned)data->estimated_range_km);
    }

    lv_obj_t *lbl_range = lv_label_create(parent);
    lv_label_set_text(lbl_range, range_buf);
    lv_obj_set_style_text_font(lbl_range, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_range, col_text, 0);
    lv_obj_set_style_text_align(lbl_range, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_range, LV_ALIGN_CENTER, 0, 55);

    /* --- Range label --- */
    lv_obj_t *lbl_range_label = lv_label_create(parent);
    lv_label_set_text(lbl_range_label, "Range");
    lv_obj_set_style_text_font(lbl_range_label, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_range_label, col_muted, 0);
    lv_obj_set_style_text_align(lbl_range_label, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_range_label, LV_ALIGN_CENTER, 0, 85);

    /* --- Divider line --- */
    lv_obj_t *divider = lv_obj_create(parent);
    lv_obj_set_size(divider, 240, 1);
    lv_obj_set_style_bg_color(divider, SCRAM_COLOR_INACTIVE, 0);
    lv_obj_set_style_bg_opa(divider, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(divider, 0, 0);
    lv_obj_clear_flag(divider, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(divider, LV_ALIGN_CENTER, 0, 105);

    /* --- Consumption (left column) --- */
    /* Convert ml_per_km to L/100km: multiply by 0.1 */
    char cons_val_buf[16];
    if (data->consumption_ml_per_km == 0xFFFF) {
        snprintf(cons_val_buf, sizeof(cons_val_buf), "--");
    } else {
        uint16_t l_per_100 = data->consumption_ml_per_km; /* ml/km * 100/1000 = /10 */
        snprintf(cons_val_buf, sizeof(cons_val_buf), "%u.%uL",
                 (unsigned)(l_per_100 / 10), (unsigned)(l_per_100 % 10));
    }

    lv_obj_t *lbl_cons_val = lv_label_create(parent);
    lv_label_set_text(lbl_cons_val, cons_val_buf);
    lv_obj_set_style_text_font(lbl_cons_val, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_cons_val, col_fill, 0);
    lv_obj_align(lbl_cons_val, LV_ALIGN_CENTER, -65, 125);

    lv_obj_t *lbl_cons_unit = lv_label_create(parent);
    lv_label_set_text(lbl_cons_unit, "/100km");
    lv_obj_set_style_text_font(lbl_cons_unit, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_cons_unit, col_muted, 0);
    lv_obj_align(lbl_cons_unit, LV_ALIGN_CENTER, -65, 143);

    /* --- Fuel remaining (right column) --- */
    /* Convert fuel_remaining_ml to liters: divide by 1000 */
    char remain_val_buf[16];
    if (data->fuel_remaining_ml == 0xFFFF) {
        snprintf(remain_val_buf, sizeof(remain_val_buf), "--");
    } else {
        uint16_t liters_x10 = data->fuel_remaining_ml / 100; /* ml/100 = dL, /10 = L */
        snprintf(remain_val_buf, sizeof(remain_val_buf), "%u.%uL",
                 (unsigned)(liters_x10 / 10), (unsigned)(liters_x10 % 10));
    }

    lv_obj_t *lbl_remain_val = lv_label_create(parent);
    lv_label_set_text(lbl_remain_val, remain_val_buf);
    lv_obj_set_style_text_font(lbl_remain_val, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_remain_val, col_blue, 0);
    lv_obj_align(lbl_remain_val, LV_ALIGN_CENTER, 65, 125);

    lv_obj_t *lbl_remain_unit = lv_label_create(parent);
    lv_label_set_text(lbl_remain_unit, "in tank");
    lv_obj_set_style_text_font(lbl_remain_unit, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_remain_unit, col_muted, 0);
    lv_obj_align(lbl_remain_unit, LV_ALIGN_CENTER, 65, 143);
}
