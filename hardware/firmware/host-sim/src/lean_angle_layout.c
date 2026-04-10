/*
 * lean_angle_layout.c — pure math helpers for the lean angle screen.
 *
 * No framebuffer access; everything here is unit-testable.
 */
#include "lean_angle_layout.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* Visual range of the gauge arc, in tenths of a degree.
 * The needle is clipped to this range before being projected so the
 * tip never wanders past the visible scale. */
#define LEAN_GAUGE_VISUAL_MAX_X10 600

void lean_arc_needle_endpoint(int16_t lean_x10, int center_x, int center_y, int radius, int *out_x,
                              int *out_y)
{
    int32_t clipped = (int32_t)lean_x10;
    if (clipped > LEAN_GAUGE_VISUAL_MAX_X10) {
        clipped = LEAN_GAUGE_VISUAL_MAX_X10;
    } else if (clipped < -LEAN_GAUGE_VISUAL_MAX_X10) {
        clipped = -LEAN_GAUGE_VISUAL_MAX_X10;
    }

    /* Convert to radians. Positive lean = right => needle leans toward
     * the right side of the screen (positive x offset). */
    const double theta_rad = ((double)clipped / 10.0) * (M_PI / 180.0);
    const double x_offset = sin(theta_rad) * (double)radius;
    const double y_offset = cos(theta_rad) * (double)radius;

    /* Screen y grows down, the gauge sits ABOVE the centre, so the tip
     * is at center_y - y_offset. The needle base is at (cx, cy). */
    if (out_x != NULL) {
        *out_x = center_x + (int)lround(x_offset);
    }
    if (out_y != NULL) {
        *out_y = center_y - (int)lround(y_offset);
    }
}

/* Round half-away-from-zero to whole degrees. */
static int round_lean_to_whole_deg(int32_t lean_x10)
{
    const int sign = (lean_x10 < 0) ? -1 : 1;
    const int32_t abs_x10 = (lean_x10 < 0) ? -lean_x10 : lean_x10;
    return sign * (int)((abs_x10 + 5) / 10);
}

size_t format_lean_digital(int16_t lean_x10, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0) {
        return 0;
    }
    const int whole = round_lean_to_whole_deg((int32_t)lean_x10);
    int written;
    if (whole == 0) {
        written = snprintf(buf, buf_len, "0");
    } else if (whole > 0) {
        written = snprintf(buf, buf_len, "R %d", whole);
    } else {
        written = snprintf(buf, buf_len, "L %d", -whole);
    }
    if (written < 0 || (size_t)written >= buf_len) {
        return 0;
    }
    return (size_t)written;
}

size_t format_max_lean(uint16_t lean_x10, char side, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0) {
        return 0;
    }
    if (side != 'L' && side != 'R') {
        return 0;
    }
    const int whole = (int)(((uint32_t)lean_x10 + 5U) / 10U);
    const int written = snprintf(buf, buf_len, "MAX %c %d", side, whole);
    if (written < 0 || (size_t)written >= buf_len) {
        return 0;
    }
    return (size_t)written;
}
