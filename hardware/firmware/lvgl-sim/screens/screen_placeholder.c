/*
 * screen_placeholder.c — fallback screen for unimplemented screen IDs.
 *
 * Shows a centered label with the screen name in large muted text.
 * Used by screen_manager when a screen ID doesn't have a real LVGL
 * implementation yet.
 *
 * ESP-IDF compatible: pure LVGL, no SDL dependencies.
 */
#include "screens/screen_placeholder.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"

void screen_placeholder_create(lv_obj_t *parent, const char *screen_name)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_label_set_text(label, screen_name);
    lv_obj_set_style_text_font(label, SCRAM_FONT_VALUE, 0);
    lv_obj_set_style_text_color(label, SCRAM_COLOR_MUTED, 0);
    lv_obj_set_style_text_align(label, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_center(label);
}
