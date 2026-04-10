/*
 * lean_angle_layout.h — pure math helpers for the lean angle screen.
 *
 * Kept as a separate translation unit so the trigonometry that places
 * the gauge needle and the formatters that build the digital readouts
 * can be unit-tested with Unity without touching the framebuffer.
 *
 * Sign convention (matches the wire format and ScramCore calculator):
 *   current_lean_x10 < 0  => left lean
 *   current_lean_x10 > 0  => right lean
 *   current_lean_x10 == 0 => upright
 *
 * The arc is drawn at the top half of the canvas spanning roughly
 * -60° (left) to +60° (right). The needle is rooted at the gauge centre
 * and its tip lands on the arc circle at the angle corresponding to the
 * current lean value.
 */
#ifndef HOST_SIM_LEAN_ANGLE_LAYOUT_H
#define HOST_SIM_LEAN_ANGLE_LAYOUT_H

#include <stddef.h>
#include <stdint.h>

/*
 * Compute the (x,y) endpoint of the gauge needle for the given lean
 * angle. The needle is rooted at (center_x, center_y); its tip is on
 * the circle of radius `radius` at the angle corresponding to the
 * current lean. Lean values are clamped to ±60° before being placed
 * on the arc so the needle never wanders past the visible scale.
 *
 * Output is via out parameters so callers can use stack ints without
 * fighting struct returns.
 */
void lean_arc_needle_endpoint(int16_t lean_x10, int center_x, int center_y, int radius, int *out_x,
                              int *out_y);

/*
 * Format the centred digital readout. Output examples:
 *   "0"        (upright)
 *   "L 25"     (25.0° left lean — rounded down to whole degrees)
 *   "R 42"     (42.5° right lean rounds half-away-from-zero)
 *
 * The buffer must be at least 8 bytes. Returns the number of characters
 * written (excluding the terminator), or 0 if the buffer is too small.
 */
size_t format_lean_digital(int16_t lean_x10, char *buf, size_t buf_len);

/*
 * Format the max-side digital readout. `side` is 'L' or 'R' for left/
 * right respectively. Output example: "MAX L 58", "MAX R 62".
 *
 * The buffer must be at least 12 bytes.
 */
size_t format_max_lean(uint16_t lean_x10, char side, char *buf, size_t buf_len);

#endif /* HOST_SIM_LEAN_ANGLE_LAYOUT_H */
