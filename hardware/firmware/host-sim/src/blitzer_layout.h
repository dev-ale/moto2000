/*
 * blitzer_layout.h — pure format helpers for the blitzer (radar) alert overlay.
 *
 * Layout choices:
 *   - Distance: hero text, metres if <1000, km with one decimal otherwise.
 *   - Speed limit: "LIMIT 80" or "LIMIT --" if unknown.
 *   - Camera type: short label for the type of camera.
 *   - Speeding detection: current speed vs limit.
 */
#ifndef HOST_SIM_BLITZER_LAYOUT_H
#define HOST_SIM_BLITZER_LAYOUT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/*
 * Format distance for display.
 * < 1000m: "500M"
 * >= 1000m: "1.2KM"
 */
void format_blitzer_distance(uint16_t meters, char *buf, size_t buf_len);

/*
 * Format speed limit for display.
 * Known: "LIMIT 80"
 * Unknown (0xFFFF): "LIMIT --"
 */
void format_speed_limit(uint16_t limit_kmh, char *buf, size_t buf_len);

/*
 * Format camera type for display.
 * Returns "FIXED", "MOBILE", "RED LIGHT", "SECTION", or "UNKNOWN".
 */
void format_camera_type(uint8_t type, char *buf, size_t buf_len);

/*
 * Returns true if current speed exceeds the limit.
 * Always false if limit is unknown (0xFFFF).
 */
bool is_speeding(uint16_t current_x10, uint16_t limit_kmh);

#endif /* HOST_SIM_BLITZER_LAYOUT_H */
