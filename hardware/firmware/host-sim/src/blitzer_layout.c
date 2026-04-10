/*
 * blitzer_layout.c — pure helpers for the blitzer (radar) alert overlay.
 */
#include "blitzer_layout.h"

#include <stdio.h>
#include <string.h>

#include "ble_protocol.h"

void format_blitzer_distance(uint16_t meters, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0) {
        return;
    }
    if (meters < 1000U) {
        snprintf(buf, buf_len, "%uM", (unsigned)meters);
    } else {
        unsigned whole = meters / 1000U;
        unsigned frac  = (meters % 1000U) / 100U;
        snprintf(buf, buf_len, "%u.%uKM", whole, frac);
    }
}

void format_speed_limit(uint16_t limit_kmh, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0) {
        return;
    }
    if (limit_kmh == BLE_BLITZER_UNKNOWN_SPEED_LIMIT) {
        snprintf(buf, buf_len, "LIMIT --");
    } else {
        snprintf(buf, buf_len, "LIMIT %u", (unsigned)limit_kmh);
    }
}

void format_camera_type(uint8_t type, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0) {
        return;
    }
    switch ((ble_camera_type_t)type) {
        case BLE_CAMERA_TYPE_FIXED:
            snprintf(buf, buf_len, "FIXED");
            break;
        case BLE_CAMERA_TYPE_MOBILE:
            snprintf(buf, buf_len, "MOBILE");
            break;
        case BLE_CAMERA_TYPE_RED_LIGHT:
            snprintf(buf, buf_len, "RED LIGHT");
            break;
        case BLE_CAMERA_TYPE_SECTION:
            snprintf(buf, buf_len, "SECTION");
            break;
        default:
            snprintf(buf, buf_len, "UNKNOWN");
            break;
    }
}

bool is_speeding(uint16_t current_x10, uint16_t limit_kmh)
{
    if (limit_kmh == BLE_BLITZER_UNKNOWN_SPEED_LIMIT) {
        return false;
    }
    /* current_x10 is speed * 10, limit_kmh is whole km/h.
     * Compare: current_x10 > limit_kmh * 10 */
    return current_x10 > (uint16_t)(limit_kmh * 10U);
}
