/*
 * weather_layout.c — pure helpers for the weather screen.
 */
#include "weather_layout.h"

#include <stdio.h>
#include <string.h>

/* Truncation toward zero. The int division in C already truncates toward
 * zero for the C99 `/` operator on integers, which is exactly what we want. */
void host_sim_weather_format_temperature(int16_t celsius_x10, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0U) {
        return;
    }
    const int whole = (int)(celsius_x10 / 10); /* truncates toward zero */
    (void)snprintf(buf, buf_len, "%d", whole);
}

void host_sim_weather_format_high_low(int16_t high_x10, int16_t low_x10, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0U) {
        return;
    }
    const int high = (int)(high_x10 / 10);
    const int low = (int)(low_x10 / 10);
    (void)snprintf(buf, buf_len, "H %d  L %d", high, low);
}

void host_sim_weather_uppercase_location(const char *in, char *out, size_t out_len)
{
    if (out == NULL || out_len == 0U) {
        return;
    }
    if (in == NULL) {
        out[0] = '\0';
        return;
    }
    const size_t max_chars = WEATHER_LAYOUT_MAX_LOCATION_CHARS;
    size_t i = 0U;
    while (i < max_chars && (i + 1U) < out_len && in[i] != '\0') {
        const char c = in[i];
        if (c >= 'a' && c <= 'z') {
            out[i] = (char)(c - 'a' + 'A');
        } else {
            out[i] = c;
        }
        ++i;
    }
    out[i] = '\0';
}

void host_sim_weather_glyph_bounds(ble_weather_condition_t cond, int *out_w, int *out_h)
{
    int w = 0;
    int h = 0;
    /* All bundled glyphs share the same ~64x48 bounding box per the spec. */
    switch (cond) {
    case BLE_WEATHER_CLEAR:
    case BLE_WEATHER_CLOUDY:
    case BLE_WEATHER_RAIN:
    case BLE_WEATHER_SNOW:
    case BLE_WEATHER_FOG:
    case BLE_WEATHER_THUNDERSTORM:
        w = 64;
        h = 48;
        break;
    default:
        w = 0;
        h = 0;
        break;
    }
    if (out_w != NULL) {
        *out_w = w;
    }
    if (out_h != NULL) {
        *out_h = h;
    }
}
