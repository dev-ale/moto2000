/*
 * scram_theme.h — custom LVGL theme for ScramScreen.
 *
 * ESP-IDF compatible: pure LVGL, no SDL dependencies.
 */
#ifndef SCRAM_THEME_H
#define SCRAM_THEME_H

#include "lvgl.h"
#include <stdbool.h>

/*
 * Initialise and apply the ScramScreen theme to the given display.
 * Call once after lv_init() and display creation.
 */
void scram_theme_apply(lv_display_t *disp);

/*
 * Toggle night mode (red-on-black palette). When enabled the theme
 * swaps primary text to dim red and muted text to very dark red.
 * Callers should rebuild the active screen after toggling.
 */
void scram_theme_set_night_mode(bool enabled);

/*
 * Query the current night mode state.
 */
bool scram_theme_is_night_mode(void);

#endif /* SCRAM_THEME_H */
