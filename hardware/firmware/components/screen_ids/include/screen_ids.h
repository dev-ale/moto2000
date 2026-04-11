/*
 * screen_ids.h — Single source of truth for screen IDs and count.
 *
 * Every firmware component that works with screen IDs should include
 * this header instead of defining its own constants. Adding a new
 * screen means updating ONLY this file — the rest follows.
 *
 * Pure C, no ESP-IDF dependencies.
 */
#ifndef SCRAMSCREEN_SCREEN_IDS_H
#define SCRAMSCREEN_SCREEN_IDS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    BLE_SCREEN_NAVIGATION = 0x01,
    BLE_SCREEN_SPEED_HEADING = 0x02,
    BLE_SCREEN_COMPASS = 0x03,
    BLE_SCREEN_WEATHER = 0x04,
    BLE_SCREEN_TRIP_STATS = 0x05,
    BLE_SCREEN_MUSIC = 0x06,
    BLE_SCREEN_LEAN_ANGLE = 0x07,
    BLE_SCREEN_BLITZER = 0x08,
    BLE_SCREEN_INCOMING_CALL = 0x09,
    BLE_SCREEN_FUEL_ESTIMATE = 0x0A,
    BLE_SCREEN_ALTITUDE = 0x0B,
    BLE_SCREEN_APPOINTMENT = 0x0C,
    BLE_SCREEN_CLOCK = 0x0D,
} ble_screen_id_t;

/* Derived constants — update automatically when the enum changes. */
#define BLE_SCREEN_ID_MIN ((uint8_t)0x01u)
#define BLE_SCREEN_ID_MAX ((uint8_t)0x0Du)
#define BLE_SCREEN_COUNT  ((uint8_t)(BLE_SCREEN_ID_MAX - BLE_SCREEN_ID_MIN + 1u))

#ifdef __cplusplus
}
#endif

#endif /* SCRAMSCREEN_SCREEN_IDS_H */
