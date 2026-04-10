/*
 * screen_music.h — music player screen (matches docs/mockups.html "Music").
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_MUSIC_H
#define SCREEN_MUSIC_H

#include "lvgl.h"
#include "ble_protocol.h"

/*
 * Populate `parent` with the music screen layout:
 *   - Album art placeholder (rounded rect with music note glyph)
 *   - Track title
 *   - Artist name
 *   - Progress bar with scrubber dot
 *   - Time labels (position / duration)
 */
void screen_music_create(lv_obj_t *parent, const ble_music_data_t *data, uint8_t flags);

#endif /* SCREEN_MUSIC_H */
