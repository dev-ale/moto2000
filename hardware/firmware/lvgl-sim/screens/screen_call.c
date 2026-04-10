/*
 * screen_call.c — incoming call screen with avatar and status
 *                  (matches docs/mockups-extra.html).
 *
 * Layout:
 *   - Pulsing ring:    static glow ring (outer circle, reduced opacity)
 *   - Avatar circle:   #333 circle with caller's initial letter, white
 *   - Caller name:     full caller_handle, white, medium
 *   - State text:      "INCOMING CALL" / "CONNECTED" / "CALL ENDED", green
 *   - Accept button:   green circle with checkmark (decorative)
 *   - Reject button:   red circle with X (decorative)
 *   - Button labels:   "Accept" / "Reject", muted gray
 *
 * This is an alert overlay. The ALERT flag is set for incoming/connected.
 *
 * Night mode: red palette. The green accept button intentionally stays
 * green for contrast — this is a deliberate design choice so the accept
 * action remains visually distinct even in night mode.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_call.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <stdio.h>
#include <ctype.h>

/* ------------------------------------------------------------------ */
/*  State text mapping                                                  */
/* ------------------------------------------------------------------ */

static const char *call_state_text(ble_call_state_t state)
{
    switch (state) {
        case BLE_CALL_INCOMING:  return "INCOMING CALL";
        case BLE_CALL_CONNECTED: return "CONNECTED";
        case BLE_CALL_ENDED:     return "CALL ENDED";
    }
    return "UNKNOWN";
}

/* ------------------------------------------------------------------ */
/*  Screen layout                                                      */
/* ------------------------------------------------------------------ */

void screen_call_create(lv_obj_t *parent,
                        const ble_incoming_call_data_t *data,
                        uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text   = night ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_WHITE;
    lv_color_t col_muted  = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    /* Green accept button stays green even in night mode (intentional). */
    lv_color_t col_green  = SCRAM_COLOR_GREEN;
    lv_color_t col_red    = SCRAM_COLOR_RED;
    lv_color_t col_state  = night ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_GREEN;
    lv_color_t col_avatar = night ? lv_color_hex(0x220000)  : lv_color_hex(0x333333);

    (void)flags;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* --- Static glow ring (outermost) --- */
    lv_obj_t *glow_ring = lv_obj_create(parent);
    lv_obj_set_size(glow_ring, 150, 150);
    lv_obj_set_style_radius(glow_ring, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(glow_ring, col_green, 0);
    lv_obj_set_style_bg_opa(glow_ring, LV_OPA_20, 0);
    lv_obj_set_style_border_width(glow_ring, 0, 0);
    lv_obj_clear_flag(glow_ring, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(glow_ring, LV_ALIGN_CENTER, 0, -60);

    /* --- Middle glow ring --- */
    lv_obj_t *mid_ring = lv_obj_create(parent);
    lv_obj_set_size(mid_ring, 120, 120);
    lv_obj_set_style_radius(mid_ring, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(mid_ring, col_green, 0);
    lv_obj_set_style_bg_opa(mid_ring, LV_OPA_30, 0);
    lv_obj_set_style_border_width(mid_ring, 0, 0);
    lv_obj_clear_flag(mid_ring, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(mid_ring, LV_ALIGN_CENTER, 0, -60);

    /* --- Avatar circle --- */
    lv_obj_t *avatar = lv_obj_create(parent);
    lv_obj_set_size(avatar, 90, 90);
    lv_obj_set_style_radius(avatar, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(avatar, col_avatar, 0);
    lv_obj_set_style_bg_opa(avatar, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(avatar, 0, 0);
    lv_obj_clear_flag(avatar, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(avatar, LV_ALIGN_CENTER, 0, -60);

    /* Initial letter (first char of caller_handle, uppercased). */
    char initial_buf[4] = "?";
    if (data->caller_handle[0] != '\0') {
        initial_buf[0] = (char)toupper((unsigned char)data->caller_handle[0]);
        initial_buf[1] = '\0';
    }

    lv_obj_t *lbl_initial = lv_label_create(parent);
    lv_label_set_text(lbl_initial, initial_buf);
    lv_obj_set_style_text_font(lbl_initial, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_initial, col_text, 0);
    lv_obj_set_style_text_align(lbl_initial, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_initial, LV_ALIGN_CENTER, 0, -60);

    /* --- Caller name --- */
    lv_obj_t *lbl_name = lv_label_create(parent);
    lv_label_set_text(lbl_name, data->caller_handle);
    lv_obj_set_style_text_font(lbl_name, SCRAM_FONT_VALUE, 0);
    lv_obj_set_style_text_color(lbl_name, col_text, 0);
    lv_obj_set_style_text_align(lbl_name, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_width(lbl_name, 300);
    lv_label_set_long_mode(lbl_name, LV_LABEL_LONG_DOT);
    lv_obj_align(lbl_name, LV_ALIGN_CENTER, 0, 10);

    /* --- State text --- */
    lv_obj_t *lbl_state = lv_label_create(parent);
    lv_label_set_text(lbl_state, call_state_text(data->call_state));
    lv_obj_set_style_text_font(lbl_state, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_state, col_state, 0);
    lv_obj_set_style_text_align(lbl_state, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_state, LV_ALIGN_CENTER, 0, 42);

    /* --- Decorative accept/reject buttons --- */
    /* Accept button (green circle with checkmark). */
    lv_obj_t *btn_accept = lv_obj_create(parent);
    lv_obj_set_size(btn_accept, 50, 50);
    lv_obj_set_style_radius(btn_accept, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(btn_accept, col_green, 0);
    lv_obj_set_style_bg_opa(btn_accept, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(btn_accept, 0, 0);
    lv_obj_clear_flag(btn_accept, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(btn_accept, LV_ALIGN_CENTER, -60, 100);

    lv_obj_t *lbl_check = lv_label_create(btn_accept);
    lv_label_set_text(lbl_check, LV_SYMBOL_OK);
    lv_obj_set_style_text_color(lbl_check, SCRAM_COLOR_WHITE, 0);
    lv_obj_set_style_text_font(lbl_check, SCRAM_FONT_VALUE, 0);
    lv_obj_center(lbl_check);

    lv_obj_t *lbl_accept = lv_label_create(parent);
    lv_label_set_text(lbl_accept, "Accept");
    lv_obj_set_style_text_font(lbl_accept, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_accept, col_muted, 0);
    lv_obj_set_style_text_align(lbl_accept, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_accept, LV_ALIGN_CENTER, -60, 133);

    /* Reject button (red circle with X). */
    lv_obj_t *btn_reject = lv_obj_create(parent);
    lv_obj_set_size(btn_reject, 50, 50);
    lv_obj_set_style_radius(btn_reject, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(btn_reject, col_red, 0);
    lv_obj_set_style_bg_opa(btn_reject, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(btn_reject, 0, 0);
    lv_obj_clear_flag(btn_reject, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(btn_reject, LV_ALIGN_CENTER, 60, 100);

    lv_obj_t *lbl_x = lv_label_create(btn_reject);
    lv_label_set_text(lbl_x, LV_SYMBOL_CLOSE);
    lv_obj_set_style_text_color(lbl_x, SCRAM_COLOR_WHITE, 0);
    lv_obj_set_style_text_font(lbl_x, SCRAM_FONT_VALUE, 0);
    lv_obj_center(lbl_x);

    lv_obj_t *lbl_reject = lv_label_create(parent);
    lv_label_set_text(lbl_reject, "Reject");
    lv_obj_set_style_text_font(lbl_reject, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_reject, col_muted, 0);
    lv_obj_set_style_text_align(lbl_reject, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_reject, LV_ALIGN_CENTER, 60, 133);
}
