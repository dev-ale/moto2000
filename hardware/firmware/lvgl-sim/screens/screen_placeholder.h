/*
 * screen_placeholder.h — fallback screen for unimplemented screen IDs.
 *
 * ESP-IDF compatible: pure LVGL, no SDL dependencies.
 */
#ifndef SCREEN_PLACEHOLDER_H
#define SCREEN_PLACEHOLDER_H

#include "lvgl.h"

/*
 * Populate `parent` with a centered label showing the screen name
 * in large muted text.
 */
void screen_placeholder_create(lv_obj_t *parent, const char *screen_name);

#endif /* SCREEN_PLACEHOLDER_H */
