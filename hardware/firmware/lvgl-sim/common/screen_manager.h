/*
 * screen_manager.h — dispatches BLE payloads to LVGL screen implementations.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#ifndef SCREEN_MANAGER_H
#define SCREEN_MANAGER_H

#include <stdbool.h>
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
 * Seed the cache with one default-encoded payload for every known
 * screen ID. After this call, the user can interactively cycle through
 * every screen even before iOS streams real data, and any subsequent
 * `screen_manager_update_live()` call will overwrite the placeholder
 * with live data.
 */
void screen_manager_seed_placeholders(void);

/*
 * Switch to the next/previous cached screen (arrow-key navigation).
 */
void screen_manager_next_screen(void);
void screen_manager_prev_screen(void);

/*
 * Re-render the currently selected screen from the cache.
 * No-op if the cache is empty.
 */
void screen_manager_show_current(void);

/*
 * Toggle night mode and re-render the current screen.
 */
void screen_manager_toggle_night(void);

/*
 * Copy the cached BLE payload (header + body) for a screen into out_buf.
 * Returns true if a cached payload exists and fits in out_buf.
 *
 * Used by screens that want to overlay data from another screen — e.g.
 * the clock screen rendering current weather underneath the time.
 */
bool screen_manager_get_cached(uint8_t screen_id, uint8_t *out_buf, size_t out_cap,
                               size_t *out_len);

#endif /* SCREEN_MANAGER_H */
