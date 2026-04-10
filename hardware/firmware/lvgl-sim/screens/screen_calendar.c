/*
 * screen_calendar.c — calendar event screen with event card
 *                      (matches docs/mockups-extra.html).
 *
 * Layout:
 *   - Title:      "NEXT EVENT"       SCRAM_FONT_SMALL, muted gray, top
 *   - Event card: rounded rect with colored left border (#5BACF5 blue)
 *     - Title:    e.g. "Sprint Review"  SCRAM_FONT_VALUE, white
 *     - Time:     e.g. "15:00"          SCRAM_FONT_LABEL, blue accent
 *     - Location: e.g. "Teams"          SCRAM_FONT_SMALL, muted gray
 *   - Countdown:  "IN 42M"           SCRAM_FONT_HERO, orange accent
 *
 * Night mode: red palette, card border becomes red.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_calendar.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <stdio.h>
#include <stdlib.h>

/* ------------------------------------------------------------------ */
/*  Countdown formatter                                                 */
/* ------------------------------------------------------------------ */

static void format_countdown(int16_t starts_in_minutes, char *buf, size_t cap)
{
    if (starts_in_minutes == 0) {
        snprintf(buf, cap, "NOW");
    } else if (starts_in_minutes > 0) {
        if (starts_in_minutes >= 60) {
            snprintf(buf, cap, "IN %dH %dM",
                     (int)(starts_in_minutes / 60),
                     (int)(starts_in_minutes % 60));
        } else {
            snprintf(buf, cap, "IN %dM", (int)starts_in_minutes);
        }
    } else {
        int16_t ago = (int16_t)-starts_in_minutes;
        if (ago >= 60) {
            snprintf(buf, cap, "%dH %dM AGO",
                     (int)(ago / 60), (int)(ago % 60));
        } else {
            snprintf(buf, cap, "%dM AGO", (int)ago);
        }
    }
}

/* ------------------------------------------------------------------ */
/*  Screen layout                                                      */
/* ------------------------------------------------------------------ */

void screen_calendar_create(lv_obj_t *parent,
                            const ble_appointment_data_t *data,
                            uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text   = night ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_WHITE;
    lv_color_t col_muted  = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_blue   = night ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_BLUE;
    lv_color_t col_orange = night ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_ORANGE;
    lv_color_t col_border = night ? SCRAM_COLOR_RED         : SCRAM_COLOR_BLUE;
    lv_color_t col_card   = night ? lv_color_hex(0x110000)  : lv_color_hex(0x1A1A1A);

    (void)flags;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* --- Title --- */
    lv_obj_t *lbl_title = lv_label_create(parent);
    lv_label_set_text(lbl_title, "NEXT EVENT");
    lv_obj_set_style_text_font(lbl_title, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_title, col_muted, 0);
    lv_obj_set_style_text_align(lbl_title, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_title, LV_ALIGN_TOP_MID, 0, 70);

    /* --- Event card --- */
    /* Card background: rounded rectangle. */
    lv_obj_t *card = lv_obj_create(parent);
    lv_obj_set_size(card, 300, 140);
    lv_obj_align(card, LV_ALIGN_CENTER, 0, -20);
    lv_obj_set_style_radius(card, 12, 0);
    lv_obj_set_style_bg_color(card, col_card, 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(card, 0, 0);
    lv_obj_set_style_pad_left(card, 20, 0);
    lv_obj_set_style_pad_top(card, 20, 0);
    lv_obj_set_style_pad_right(card, 15, 0);
    lv_obj_set_style_pad_bottom(card, 15, 0);
    lv_obj_clear_flag(card, LV_OBJ_FLAG_SCROLLABLE);

    /* Left accent border: a narrow rect on the left side of the card. */
    lv_obj_t *accent_bar = lv_obj_create(parent);
    lv_obj_set_size(accent_bar, 4, 120);
    /* Position it aligned with the card's left edge. */
    lv_obj_align_to(accent_bar, card, LV_ALIGN_OUT_LEFT_MID, 0, 0);
    /* Overlap it into the card by shifting right. */
    lv_obj_align(accent_bar, LV_ALIGN_CENTER, -148, -20);
    lv_obj_set_style_radius(accent_bar, 2, 0);
    lv_obj_set_style_bg_color(accent_bar, col_border, 0);
    lv_obj_set_style_bg_opa(accent_bar, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(accent_bar, 0, 0);
    lv_obj_clear_flag(accent_bar, LV_OBJ_FLAG_SCROLLABLE);

    /* Event title inside card. */
    lv_obj_t *lbl_event = lv_label_create(card);
    lv_label_set_text(lbl_event, data->title);
    lv_obj_set_style_text_font(lbl_event, SCRAM_FONT_VALUE, 0);
    lv_obj_set_style_text_color(lbl_event, col_text, 0);
    lv_obj_set_width(lbl_event, 260);
    lv_label_set_long_mode(lbl_event, LV_LABEL_LONG_DOT);
    lv_obj_align(lbl_event, LV_ALIGN_TOP_LEFT, 0, 0);

    /* Time display inside card. */
    /* Format: compute approximate start time from countdown.
     * Since we only have starts_in_minutes, we show the countdown
     * directly in the time slot as a compact form. */
    char time_buf[24];
    if (data->starts_in_minutes == 0) {
        snprintf(time_buf, sizeof(time_buf), "NOW");
    } else if (data->starts_in_minutes > 0) {
        snprintf(time_buf, sizeof(time_buf), "IN %d MIN",
                 (int)data->starts_in_minutes);
    } else {
        snprintf(time_buf, sizeof(time_buf), "%d MIN AGO",
                 (int)(-data->starts_in_minutes));
    }

    lv_obj_t *lbl_time = lv_label_create(card);
    lv_label_set_text(lbl_time, time_buf);
    lv_obj_set_style_text_font(lbl_time, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_time, col_blue, 0);
    lv_obj_align(lbl_time, LV_ALIGN_TOP_LEFT, 0, 35);

    /* Location inside card. */
    if (data->location[0] != '\0') {
        lv_obj_t *lbl_loc = lv_label_create(card);
        lv_label_set_text(lbl_loc, data->location);
        lv_obj_set_style_text_font(lbl_loc, SCRAM_FONT_SMALL, 0);
        lv_obj_set_style_text_color(lbl_loc, col_muted, 0);
        lv_obj_set_width(lbl_loc, 260);
        lv_label_set_long_mode(lbl_loc, LV_LABEL_LONG_DOT);
        lv_obj_align(lbl_loc, LV_ALIGN_TOP_LEFT, 0, 65);
    }

    /* --- Countdown --- */
    char countdown_buf[32];
    format_countdown(data->starts_in_minutes, countdown_buf,
                     sizeof(countdown_buf));

    lv_obj_t *lbl_countdown = lv_label_create(parent);
    lv_label_set_text(lbl_countdown, countdown_buf);
    lv_obj_set_style_text_font(lbl_countdown, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_countdown, col_orange, 0);
    lv_obj_set_style_text_align(lbl_countdown, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_countdown, LV_ALIGN_CENTER, 0, 110);
}
