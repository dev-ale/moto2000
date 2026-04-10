/*
 * scram_theme.c — custom LVGL theme for ScramScreen.
 *
 * Sets default styles matching docs/mockups.html:
 *   - Background: #0a0a0a (near-black)
 *   - Text: #ffffff
 *   - Arc/bar inactive: #222222
 *   - Arc/bar active: #4dd88a (green)
 *
 * Night mode swaps to a red-on-black palette.
 *
 * ESP-IDF compatible: pure LVGL, no SDL dependencies.
 */
#include "theme/scram_theme.h"
#include "theme/scram_colors.h"

/* Need the private header for the full lv_theme_t struct definition.
   This is standard practice for custom LVGL v9 themes. */
#include "src/themes/lv_theme_private.h"

static bool       s_night_mode;
static lv_theme_t s_theme;

/* Base styles applied to every object via theme callbacks. */
static lv_style_t s_style_bg;
static lv_style_t s_style_label;
static lv_style_t s_style_arc_bg;
static lv_style_t s_style_arc_fg;
static lv_style_t s_style_bar_bg;
static lv_style_t s_style_bar_fg;

static void theme_apply_cb(lv_theme_t *th, lv_obj_t *obj)
{
    /* Screen (top-level objects with no parent are screens in LVGL v9) */
    if (lv_obj_get_parent(obj) == NULL) {
        lv_obj_add_style(obj, &s_style_bg, 0);
        return;
    }

    /* Labels */
    if (lv_obj_check_type(obj, &lv_label_class)) {
        lv_obj_add_style(obj, &s_style_label, 0);
        return;
    }

    /* Arcs */
    if (lv_obj_check_type(obj, &lv_arc_class)) {
        lv_obj_add_style(obj, &s_style_arc_bg, LV_PART_MAIN);
        lv_obj_add_style(obj, &s_style_arc_fg, LV_PART_INDICATOR);
        return;
    }

    /* Bars */
    if (lv_obj_check_type(obj, &lv_bar_class)) {
        lv_obj_add_style(obj, &s_style_bar_bg, LV_PART_MAIN);
        lv_obj_add_style(obj, &s_style_bar_fg, LV_PART_INDICATOR);
        return;
    }
}

static void rebuild_styles(void)
{
    lv_color_t bg    = s_night_mode ? SCRAM_COLOR_NIGHT_BG    : SCRAM_COLOR_BG;
    lv_color_t text  = s_night_mode ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_WHITE;
    lv_color_t green = s_night_mode ? SCRAM_COLOR_NIGHT_TEXT  : SCRAM_COLOR_GREEN;

    /* Background */
    lv_style_reset(&s_style_bg);
    lv_style_set_bg_color(&s_style_bg, bg);
    lv_style_set_bg_opa(&s_style_bg, LV_OPA_COVER);

    /* Label text */
    lv_style_reset(&s_style_label);
    lv_style_set_text_color(&s_style_label, text);

    /* Arc background (inactive track) */
    lv_style_reset(&s_style_arc_bg);
    lv_style_set_arc_color(&s_style_arc_bg, SCRAM_COLOR_INACTIVE);

    /* Arc foreground (active indicator) */
    lv_style_reset(&s_style_arc_fg);
    lv_style_set_arc_color(&s_style_arc_fg, green);

    /* Bar background */
    lv_style_reset(&s_style_bar_bg);
    lv_style_set_bg_color(&s_style_bar_bg, SCRAM_COLOR_INACTIVE);
    lv_style_set_bg_opa(&s_style_bar_bg, LV_OPA_COVER);

    /* Bar indicator */
    lv_style_reset(&s_style_bar_fg);
    lv_style_set_bg_color(&s_style_bar_fg, green);
    lv_style_set_bg_opa(&s_style_bar_fg, LV_OPA_COVER);
}

void scram_theme_apply(lv_display_t *disp)
{
    s_night_mode = false;

    lv_style_init(&s_style_bg);
    lv_style_init(&s_style_label);
    lv_style_init(&s_style_arc_bg);
    lv_style_init(&s_style_arc_fg);
    lv_style_init(&s_style_bar_bg);
    lv_style_init(&s_style_bar_fg);

    rebuild_styles();

    lv_theme_set_apply_cb(&s_theme, theme_apply_cb);

    lv_display_set_theme(disp, &s_theme);
}

void scram_theme_set_night_mode(bool enabled)
{
    if (s_night_mode == enabled) {
        return;
    }
    s_night_mode = enabled;
    rebuild_styles();
}

bool scram_theme_is_night_mode(void)
{
    return s_night_mode;
}
