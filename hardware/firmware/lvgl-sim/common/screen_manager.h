/*
 * screen_manager.h — dispatches BLE payloads to LVGL screen implementations.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_MANAGER_H
#define SCREEN_MANAGER_H

#include <stddef.h>
#include <stdint.h>

/*
 * Initialise the screen manager. Call once after LVGL and theme init.
 */
void screen_manager_init(void);

/*
 * Decode a BLE payload and render the corresponding screen.
 * Creates a new LVGL screen, populates it, and loads it.
 */
void screen_manager_handle_payload(const uint8_t *data, size_t len);

/*
 * Cache a BLE payload without switching the display. Used to pre-load
 * data for all screens so the user can interactively switch between them.
 */
void screen_manager_cache_payload(const uint8_t *data, size_t len);

/*
 * Cache a payload and re-render only if it matches the active screen.
 * Use this in live-stream mode to avoid flashing between screens.
 */
void screen_manager_update_live(const uint8_t *data, size_t len);

/*
 * Switch to the next/previous cached screen (arrow-key navigation).
 */
void screen_manager_next_screen(void);
void screen_manager_prev_screen(void);

/*
 * Toggle night mode and re-render the current screen.
 */
void screen_manager_toggle_night(void);

#endif /* SCREEN_MANAGER_H */
