/*
 * screen_music.c — music player screen with progress bar (matches docs/mockups.html).
 *
 * Layout (from the SVG mockup "Music"):
 *   - Album art placeholder:   rounded rect #333 with "M" glyph, top center
 *   - Track title:             white, medium font, centered
 *   - Artist:                  muted gray, small, centered
 *   - Progress bar:            lv_bar, green fill on dark track
 *   - Scrubber dot:            small green circle at bar fill endpoint
 *   - Time labels:             position (left), duration (right), muted gray
 *
 * Night mode: green becomes red.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_music.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <stdio.h>

/* ------------------------------------------------------------------ */
/*  Time formatting helpers                                             */
/* ------------------------------------------------------------------ */

static void format_time_mss(uint16_t seconds, char *buf, size_t cap)
{
    if (seconds == BLE_MUSIC_UNKNOWN_DURATION_OR_POSITION) {
        snprintf(buf, cap, "--:--");
        return;
    }
    unsigned m = (unsigned)(seconds / 60U);
    unsigned s = (unsigned)(seconds % 60U);
    snprintf(buf, cap, "%u:%02u", m, s);
}

/* ------------------------------------------------------------------ */
/*  Screen layout                                                      */
/* ------------------------------------------------------------------ */

void screen_music_create(lv_obj_t *parent, const ble_music_data_t *data, uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_WHITE;
    lv_color_t col_muted = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_accent = night ? SCRAM_COLOR_RED : SCRAM_COLOR_GREEN;
    lv_color_t col_art_bg = night ? lv_color_hex(0x1A0000) : lv_color_hex(0x333333);

    (void)flags;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* --- Album art placeholder --- */
    lv_obj_t *art = lv_obj_create(parent);
    lv_obj_set_size(art, 140, 140);
    lv_obj_set_style_radius(art, 20, 0);
    lv_obj_set_style_bg_color(art, col_art_bg, 0);
    lv_obj_set_style_bg_opa(art, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(art, 0, 0);
    lv_obj_clear_flag(art, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(art, LV_ALIGN_TOP_MID, 0, 68);

    /* Music note glyph inside the placeholder.
     * Use "M" as a safe fallback since built-in fonts may not have U+266B. */
    lv_obj_t *lbl_note = lv_label_create(art);
    lv_label_set_text(lbl_note, "M");
    lv_obj_set_style_text_font(lbl_note, SCRAM_FONT_VALUE, 0);
    lv_obj_set_style_text_color(lbl_note, col_muted, 0);
    lv_obj_set_style_text_align(lbl_note, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_center(lbl_note);

    /* --- Track title --- */
    lv_obj_t *lbl_title = lv_label_create(parent);
    lv_label_set_text(lbl_title, data->title);
    lv_obj_set_style_text_font(lbl_title, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_title, col_text, 0);
    lv_obj_set_style_text_align(lbl_title, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_width(lbl_title, 380);
    lv_label_set_long_mode(lbl_title, LV_LABEL_LONG_DOT);
    lv_obj_align(lbl_title, LV_ALIGN_CENTER, 0, 45);

    /* --- Artist --- */
    lv_obj_t *lbl_artist = lv_label_create(parent);
    lv_label_set_text(lbl_artist, data->artist);
    lv_obj_set_style_text_font(lbl_artist, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_artist, col_muted, 0);
    lv_obj_set_style_text_align(lbl_artist, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_width(lbl_artist, 380);
    lv_label_set_long_mode(lbl_artist, LV_LABEL_LONG_DOT);
    lv_obj_align(lbl_artist, LV_ALIGN_CENTER, 0, 70);

    /* --- Progress bar --- */
    /* Compute progress ratio. */
    int32_t bar_value = 0;
    bool has_duration = (data->duration_seconds != BLE_MUSIC_UNKNOWN_DURATION_OR_POSITION &&
                         data->duration_seconds > 0);
    bool has_position = (data->position_seconds != BLE_MUSIC_UNKNOWN_DURATION_OR_POSITION);

    if (has_duration && has_position) {
        bar_value = (int32_t)data->position_seconds * 1000 / (int32_t)data->duration_seconds;
        if (bar_value > 1000)
            bar_value = 1000;
    }

    lv_obj_t *bar = lv_bar_create(parent);
    lv_obj_set_size(bar, 280, 8);
    lv_bar_set_range(bar, 0, 1000);
    lv_bar_set_value(bar, bar_value, LV_ANIM_OFF);
    lv_obj_align(bar, LV_ALIGN_CENTER, 0, 100);

    /* Bar background (track). */
    lv_obj_set_style_bg_color(bar, SCRAM_COLOR_INACTIVE, LV_PART_MAIN);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(bar, 4, LV_PART_MAIN);

    /* Bar indicator (filled portion). */
    lv_obj_set_style_bg_color(bar, col_accent, LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_radius(bar, 4, LV_PART_INDICATOR);

    /* --- Scrubber dot --- */
    /* Position the scrubber at the bar's fill percentage. */
    int bar_x_start = -140; /* bar left edge relative to center */
    int scrubber_x = bar_x_start + (int)(280 * bar_value / 1000);

    lv_obj_t *scrubber = lv_obj_create(parent);
    lv_obj_set_size(scrubber, 16, 16);
    lv_obj_set_style_radius(scrubber, 8, 0);
    lv_obj_set_style_bg_color(scrubber, col_accent, 0);
    lv_obj_set_style_bg_opa(scrubber, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(scrubber, 0, 0);
    lv_obj_clear_flag(scrubber, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(scrubber, LV_ALIGN_CENTER, scrubber_x, 100);

    /* --- Time labels --- */
    char pos_buf[8];
    char dur_buf[8];
    format_time_mss(data->position_seconds, pos_buf, sizeof(pos_buf));
    format_time_mss(data->duration_seconds, dur_buf, sizeof(dur_buf));

    lv_obj_t *lbl_pos = lv_label_create(parent);
    lv_label_set_text(lbl_pos, pos_buf);
    lv_obj_set_style_text_font(lbl_pos, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_pos, col_muted, 0);
    lv_obj_align(lbl_pos, LV_ALIGN_CENTER, -128, 120);

    lv_obj_t *lbl_dur = lv_label_create(parent);
    lv_label_set_text(lbl_dur, dur_buf);
    lv_obj_set_style_text_font(lbl_dur, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_dur, col_muted, 0);
    lv_obj_align(lbl_dur, LV_ALIGN_CENTER, 128, 120);

    /* --- Play/pause indicator (optional small label) --- */
    bool playing = (data->music_flags & BLE_MUSIC_FLAG_PLAYING) != 0;
    lv_obj_t *lbl_state = lv_label_create(parent);
    lv_label_set_text(lbl_state, playing ? ">" : "||");
    lv_obj_set_style_text_font(lbl_state, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_state, col_muted, 0);
    lv_obj_set_style_text_align(lbl_state, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_state, LV_ALIGN_CENTER, 0, 145);
}
