/*
 * speed_layout.c — pure-C helpers for the Speed + Heading screen.
 *
 * Kept free of any canvas / SDL / PNG dependency so the logic can be
 * exercised with Unity host tests.
 */
#include "host_sim/speed_layout.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

size_t host_sim_format_speed_kmh(uint16_t speed_kmh_x10, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len < 4U) {
        return 0U;
    }
    /* Round to nearest whole km/h. */
    unsigned int kmh = ((unsigned int)speed_kmh_x10 + 5U) / 10U;
    if (kmh > 999U) {
        kmh = 999U;
    }
    if (kmh < 10U) {
        /* "  5" — two leading spaces keeps the hero glyphs stable. */
        buf[0] = ' ';
        buf[1] = ' ';
        buf[2] = (char)('0' + (int)kmh);
        buf[3] = '\0';
        return 3U;
    }
    if (kmh < 100U) {
        buf[0] = ' ';
        buf[1] = (char)('0' + (int)(kmh / 10U));
        buf[2] = (char)('0' + (int)(kmh % 10U));
        buf[3] = '\0';
        return 3U;
    }
    buf[0] = (char)('0' + (int)(kmh / 100U));
    buf[1] = (char)('0' + (int)((kmh / 10U) % 10U));
    buf[2] = (char)('0' + (int)(kmh % 10U));
    buf[3] = '\0';
    return 3U;
}

size_t host_sim_format_altitude_label(int16_t altitude_m, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len < 12U) {
        return 0U;
    }
    int clamped = (int)altitude_m;
    if (clamped < 0) {
        clamped = 0;
    }
    if (clamped > 9999) {
        clamped = 9999;
    }
    const int n = snprintf(buf, buf_len, "ALT %dM", clamped);
    if (n < 0 || (size_t)n >= buf_len) {
        return 0U;
    }
    return (size_t)n;
}

size_t host_sim_format_temperature_label(int16_t temperature_celsius_x10, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len < 8U) {
        return 0U;
    }
    /* Round half-away-from-zero. */
    int t_whole;
    if (temperature_celsius_x10 >= 0) {
        t_whole = ((int)temperature_celsius_x10 + 5) / 10;
    } else {
        t_whole = -(((int)(-temperature_celsius_x10) + 5) / 10);
    }
    if (t_whole < -99) {
        t_whole = -99;
    }
    if (t_whole > 199) {
        t_whole = 199;
    }
    const int n = snprintf(buf, buf_len, "T %dC", t_whole);
    if (n < 0 || (size_t)n >= buf_len) {
        return 0U;
    }
    return (size_t)n;
}

size_t host_sim_format_heading_label(uint16_t heading_deg_x10, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len < 8U) {
        return 0U;
    }
    unsigned int deg = (unsigned int)heading_deg_x10 / 10U;
    /* Wire format is already normalised, but be defensive. */
    deg = deg % 360U;
    char card;
    if (deg >= 315U || deg < 45U) {
        card = 'N';
    } else if (deg < 135U) {
        card = 'E';
    } else if (deg < 225U) {
        card = 'S';
    } else {
        card = 'W';
    }
    const int n = snprintf(buf, buf_len, "%c %03u", card, deg);
    if (n < 0 || (size_t)n >= buf_len) {
        return 0U;
    }
    return (size_t)n;
}

void host_sim_heading_arrow_endpoint(uint16_t heading_deg_x10, int cx, int cy, int length,
                                     int *out_x, int *out_y)
{
    if (out_x == NULL || out_y == NULL) {
        return;
    }
    const double deg = ((double)heading_deg_x10) / 10.0;
    const double rad = deg * (M_PI / 180.0);
    /* 0° = north = up. Screen-space Y grows downward. */
    const double dx = sin(rad) * (double)length;
    const double dy = -cos(rad) * (double)length;
    /* Round half-away-from-zero. */
    *out_x = cx + (int)(dx >= 0.0 ? dx + 0.5 : dx - 0.5);
    *out_y = cy + (int)(dy >= 0.0 ? dy + 0.5 : dy - 0.5);
}

void host_sim_speed_digit_origin(int canvas_w, int canvas_h, int text_len, int scale, int *out_x,
                                 int *out_y)
{
    if (out_x == NULL || out_y == NULL) {
        return;
    }
    const int glyph_w = 8 * scale;
    const int glyph_h = 8 * scale;
    const int total_w = text_len * glyph_w;
    *out_x = (canvas_w - total_w) / 2;
    /* Upper half: centre of the glyph is around 0.36 of the canvas. */
    *out_y = (canvas_h * 36) / 100 - glyph_h / 2;
}
