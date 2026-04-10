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

#endif /* SCREEN_MANAGER_H */
