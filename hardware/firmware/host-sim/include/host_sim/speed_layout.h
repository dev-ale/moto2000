/*
 * speed_layout.h — pure-C layout helpers for the Speed + Heading screen.
 *
 * Any trig, formatting, and positioning math for screen_speed.c lives
 * here so it can be unit-tested under Unity without SDL/PNG. No canvas
 * access, no globals.
 */
#ifndef HOST_SIM_SPEED_LAYOUT_H
#define HOST_SIM_SPEED_LAYOUT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Maximum representable speed on the wire is uint16_t / 10 = 6553.5 km/h,
 * but we clamp to a sane 999 for display to guarantee the hero readout
 * never exceeds 3 characters. Single-digit speeds are padded with a
 * leading space (NOT a zero) per the spec.
 *
 * `buf` must hold at least 4 bytes (3 chars + NUL). Returns strlen on
 * success, or 0 if `buf` is too small.
 */
size_t host_sim_format_speed_kmh(uint16_t speed_kmh_x10, char *buf, size_t buf_len);

/*
 * Formats altitude as "ALT <n>M". Negative altitudes are clamped to 0.
 * Values above 9999 m are clamped to 9999. `buf` needs >= 12 bytes.
 * Returns strlen on success, 0 if `buf` too small.
 */
size_t host_sim_format_altitude_label(int16_t altitude_m, char *buf, size_t buf_len);

/*
 * Formats temperature. Uses "T <n>C" form (no ° glyph in the embedded
 * 8x8 font). Signed; clamped to [-99, +199] for display sanity.
 * `buf` needs >= 8 bytes. Returns strlen on success, 0 if too small.
 */
size_t host_sim_format_temperature_label(int16_t temperature_celsius_x10, char *buf,
                                         size_t buf_len);

/*
 * Formats a compact heading label ("N 042") for the heading indicator.
 * Buf needs >= 8 bytes. Cardinal letter is one of N/E/S/W based on the
 * nearest 90° quadrant (N = [315, 45)).
 */
size_t host_sim_format_heading_label(uint16_t heading_deg_x10, char *buf, size_t buf_len);

/*
 * Projects a heading (deg * 10) to an (x, y) endpoint on a circle of
 * radius `length` around (cx, cy). Zero heading points up (north),
 * increasing clockwise — screen-space Y grows downward.
 */
void host_sim_heading_arrow_endpoint(uint16_t heading_deg_x10, int cx, int cy, int length,
                                     int *out_x, int *out_y);

/*
 * Returns the origin (top-left) for the hero speed digits, given the
 * canvas size and the chosen scale. The digit string width is
 * strlen(text)*8*scale (monospace). Centered horizontally; vertically
 * placed in the upper half of the canvas.
 */
void host_sim_speed_digit_origin(int canvas_w, int canvas_h, int text_len, int scale, int *out_x,
                                 int *out_y);

#ifdef __cplusplus
}
#endif

#endif /* HOST_SIM_SPEED_LAYOUT_H */
