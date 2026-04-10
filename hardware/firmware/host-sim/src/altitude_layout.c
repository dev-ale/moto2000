/*
 * altitude_layout.c — pure helpers for the altitude profile screen.
 */
#include "altitude_layout.h"

#include <stdio.h>
#include <stdlib.h>

int altitude_graph_y(int16_t altitude, int16_t min_alt, int16_t max_alt, int graph_top,
                     int graph_bottom)
{
    if (max_alt == min_alt) {
        /* Flat data: center vertically. */
        return (graph_top + graph_bottom) / 2;
    }
    /* Higher altitude -> lower Y (toward top of screen). */
    const int range_alt = (int)max_alt - (int)min_alt;
    const int range_px = graph_bottom - graph_top;
    const int offset = (int)altitude - (int)min_alt;
    int y = graph_bottom - (offset * range_px / range_alt);
    if (y < graph_top) {
        y = graph_top;
    }
    if (y > graph_bottom) {
        y = graph_bottom;
    }
    return y;
}

int altitude_graph_x(int sample_index, int sample_count, int graph_left, int graph_right)
{
    if (sample_count <= 1) {
        return (graph_left + graph_right) / 2;
    }
    const int range = graph_right - graph_left;
    return graph_left + (sample_index * range / (sample_count - 1));
}

void format_altitude_label(int16_t meters, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0U) {
        return;
    }
    (void)snprintf(buf, buf_len, "%dM", (int)meters);
}

void format_altitude_delta(int16_t meters, int is_ascent, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0U) {
        return;
    }
    if (is_ascent) {
        (void)snprintf(buf, buf_len, "+%uM", (unsigned)meters);
    } else {
        (void)snprintf(buf, buf_len, "-%uM", (unsigned)meters);
    }
}

/* Bresenham's line algorithm. */
static void put_pixel(host_sim_canvas_t *canvas, int x, int y, uint8_t r, uint8_t g, uint8_t b)
{
    if (x < 0 || y < 0 || x >= canvas->width || y >= canvas->height) {
        return;
    }
    const size_t idx = ((size_t)y * (size_t)canvas->width + (size_t)x) * 3U;
    canvas->pixels[idx + 0U] = r;
    canvas->pixels[idx + 1U] = g;
    canvas->pixels[idx + 2U] = b;
}

void draw_line(host_sim_canvas_t *canvas, int x0, int y0, int x1, int y1, uint8_t r, uint8_t g,
               uint8_t b)
{
    if (canvas == NULL || canvas->pixels == NULL) {
        return;
    }

    int dx = abs(x1 - x0);
    int dy = -abs(y1 - y0);
    int sx = (x0 < x1) ? 1 : -1;
    int sy = (y0 < y1) ? 1 : -1;
    int err = dx + dy;

    for (;;) {
        put_pixel(canvas, x0, y0, r, g, b);

        /* Make the line 2px thick for visibility by drawing the pixel
         * above and below (or left/right depending on orientation). */
        if (dx >= -dy) {
            /* More horizontal: thicken vertically. */
            put_pixel(canvas, x0, y0 - 1, r, g, b);
            put_pixel(canvas, x0, y0 + 1, r, g, b);
        } else {
            /* More vertical: thicken horizontally. */
            put_pixel(canvas, x0 - 1, y0, r, g, b);
            put_pixel(canvas, x0 + 1, y0, r, g, b);
        }

        if (x0 == x1 && y0 == y1) {
            break;
        }
        const int e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}
