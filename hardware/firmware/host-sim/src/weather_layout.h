/*
 * weather_layout.h — pure string/format helpers for the weather screen.
 *
 * Kept as a separate unit so the rounding, uppercasing, and bounding-box
 * math can be unit-tested under Unity without touching the framebuffer or
 * PNG writer.
 *
 * Temperature rounding: we truncate toward zero on purpose. The wire
 * temperature is already in tenths of a degree (int16 * 10), and the
 * screen displays whole degrees with no fractional part. Truncation
 * avoids the "23.5 shows as 24" rounding surprise riders see on some
 * automotive dashboards — if the upstream wants a specific display
 * value, it can round before encoding.
 */
#ifndef HOST_SIM_WEATHER_LAYOUT_H
#define HOST_SIM_WEATHER_LAYOUT_H

#include <stddef.h>
#include <stdint.h>

#include "ble_protocol.h"

/* Maximum displayed length of an uppercased location string. */
#define WEATHER_LAYOUT_MAX_LOCATION_CHARS 16

/*
 * Format a tenths-of-a-degree Celsius temperature into a whole-degree
 * string. Result examples: "22", "-3", "0", "60", "-50". The output
 * never contains a decimal point or a degree glyph; the caller is
 * responsible for appending those. Truncation rule: toward zero.
 *
 * `buf_len` must be at least 5 (sign + 3 digits + terminator).
 */
void host_sim_weather_format_temperature(int16_t celsius_x10, char *buf, size_t buf_len);

/*
 * Format the high/low line. Result example: "H 25  L 13".
 *
 * `buf_len` must be at least 16.
 */
void host_sim_weather_format_high_low(int16_t high_x10, int16_t low_x10, char *buf, size_t buf_len);

/*
 * Uppercase a location name and truncate to WEATHER_LAYOUT_MAX_LOCATION_CHARS.
 * ASCII-only — any byte outside 'a'..'z' is passed through unchanged, so
 * Latin-1 accented characters (which the embedded font can't render
 * anyway) survive as their original byte. Multi-byte UTF-8 sequences are
 * truncated in byte units; we accept the risk of splitting a glyph since
 * the font fallback draws a space for any unknown byte.
 *
 * `out_len` must be at least WEATHER_LAYOUT_MAX_LOCATION_CHARS + 1.
 */
void host_sim_weather_uppercase_location(const char *in, char *out, size_t out_len);

/*
 * Bounding box (width, height) of the glyph for a given condition. Used
 * by the renderer to center the glyph under the top of the screen.
 * Returns (0, 0) for unknown conditions.
 */
void host_sim_weather_glyph_bounds(ble_weather_condition_t cond, int *out_w, int *out_h);

#endif /* HOST_SIM_WEATHER_LAYOUT_H */
