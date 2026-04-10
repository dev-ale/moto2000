/*
 * screen_altitude.c — renders the altitude profile screen onto the round
 * 466x466 panel.
 *
 * Layout:
 *   - Background: navy day / black night.
 *   - Elevation line graph in the upper ~60% of the canvas.
 *     - Connected line segments with fill below for visual weight.
 *     - Y axis auto-scaled to data min..max with padding.
 *     - Current position marker (dot) at the rightmost sample.
 *     - Y-axis labels: min and max altitude on the left.
 *   - Below the graph:
 *     - Current altitude as large centered text: "ALT 1800M"
 *     - Ascent/descent in a row: "+1900M  -600M"
 *   - Night mode: red palette.
 */
#include "host_sim/renderer.h"
#include "text_draw.h"
#include "altitude_layout.h"

#include <stdio.h>
#include <string.h>

#include "ble_protocol.h"

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

/* Fill a vertical column from y_top to y_bottom with a dimmer shade. */
static void fill_column(host_sim_canvas_t *canvas, int x, int y_top, int y_bottom, uint8_t r,
                        uint8_t g, uint8_t b)
{
    for (int y = y_top; y <= y_bottom; ++y) {
        put_pixel(canvas, x, y, r, g, b);
    }
}

/* Draw a small filled circle as the current position marker. */
static void draw_dot(host_sim_canvas_t *canvas, int cx, int cy, int radius, uint8_t r, uint8_t g,
                     uint8_t b)
{
    for (int dy = -radius; dy <= radius; ++dy) {
        for (int dx = -radius; dx <= radius; ++dx) {
            if (dx * dx + dy * dy <= radius * radius) {
                put_pixel(canvas, cx + dx, cy + dy, r, g, b);
            }
        }
    }
}

void host_sim_render_altitude(host_sim_canvas_t *canvas, const ble_altitude_profile_data_t *alt,
                              uint8_t header_flags)
{
    const int night = (header_flags & BLE_FLAG_NIGHT_MODE) != 0U;
    if (night) {
        host_sim_canvas_fill(canvas, 0, 0, 0);
    } else {
        host_sim_canvas_fill(canvas, 0x0A, 0x1C, 0x3A);
    }

    const uint8_t text_r = night ? (uint8_t)0x88U : (uint8_t)0xFFU;
    const uint8_t text_g = night ? (uint8_t)0x11U : (uint8_t)0xFFU;
    const uint8_t text_b = night ? (uint8_t)0x11U : (uint8_t)0xFFU;

    /* Line/graph colors. */
    const uint8_t line_r = night ? (uint8_t)0xCCU : (uint8_t)0x00U;
    const uint8_t line_g = night ? (uint8_t)0x22U : (uint8_t)0xAAU;
    const uint8_t line_b = night ? (uint8_t)0x22U : (uint8_t)0xFFU;

    /* Fill-under color (dimmer). */
    const uint8_t fill_r = night ? (uint8_t)0x44U : (uint8_t)0x00U;
    const uint8_t fill_g = night ? (uint8_t)0x08U : (uint8_t)0x44U;
    const uint8_t fill_b = night ? (uint8_t)0x08U : (uint8_t)0x88U;

    /* Marker (current position) color. */
    const uint8_t mark_r = (uint8_t)0xFFU;
    const uint8_t mark_g = night ? (uint8_t)0x44U : (uint8_t)0xFFU;
    const uint8_t mark_b = night ? (uint8_t)0x44U : (uint8_t)0x00U;

    const int cx = canvas->width / 2;

    /* Graph area. */
    const int graph_left = 80;
    const int graph_right = 386;
    const int graph_top = 60;
    const int graph_bottom = 280;

    const int count = (int)alt->sample_count;

    if (count > 0) {
        /* Find min/max altitude in the profile. */
        int16_t min_alt = alt->profile[0];
        int16_t max_alt = alt->profile[0];
        for (int i = 1; i < count; ++i) {
            if (alt->profile[i] < min_alt) {
                min_alt = alt->profile[i];
            }
            if (alt->profile[i] > max_alt) {
                max_alt = alt->profile[i];
            }
        }
        /* Add some padding (at least 10m range). */
        if (max_alt - min_alt < 20) {
            min_alt = (int16_t)(min_alt - 10);
            max_alt = (int16_t)(max_alt + 10);
        } else {
            const int16_t pad = (int16_t)((max_alt - min_alt) / 10);
            min_alt = (int16_t)(min_alt - pad);
            max_alt = (int16_t)(max_alt + pad);
        }

        /* Draw fill under the line first (so the line is on top). */
        for (int i = 0; i < count; ++i) {
            const int px = altitude_graph_x(i, count, graph_left, graph_right);
            const int py =
                altitude_graph_y(alt->profile[i], min_alt, max_alt, graph_top, graph_bottom);
            fill_column(canvas, px, py, graph_bottom, fill_r, fill_g, fill_b);
        }

        /* Draw connected line segments. */
        for (int i = 0; i < count - 1; ++i) {
            const int x0 = altitude_graph_x(i, count, graph_left, graph_right);
            const int y0 =
                altitude_graph_y(alt->profile[i], min_alt, max_alt, graph_top, graph_bottom);
            const int x1 = altitude_graph_x(i + 1, count, graph_left, graph_right);
            const int y1 =
                altitude_graph_y(alt->profile[i + 1], min_alt, max_alt, graph_top, graph_bottom);
            draw_line(canvas, x0, y0, x1, y1, line_r, line_g, line_b);
        }

        /* Current position marker at rightmost sample. */
        {
            const int last_idx = count - 1;
            const int mx = altitude_graph_x(last_idx, count, graph_left, graph_right);
            const int my =
                altitude_graph_y(alt->profile[last_idx], min_alt, max_alt, graph_top, graph_bottom);
            draw_dot(canvas, mx, my, 5, mark_r, mark_g, mark_b);
        }

        /* Y-axis labels: max at top, min at bottom. */
        {
            char max_buf[12] = { 0 };
            char min_buf[12] = { 0 };
            format_altitude_label(max_alt, max_buf, sizeof(max_buf));
            format_altitude_label(min_alt, min_buf, sizeof(min_buf));
            const int label_scale = 2;
            host_sim_draw_text(canvas, max_buf, graph_left - 2, graph_top - 2, label_scale, text_r,
                               text_g, text_b);
            host_sim_draw_text(canvas, min_buf, graph_left - 2, graph_bottom + 4, label_scale,
                               text_r, text_g, text_b);
        }
    }

    /* ---- Below graph: current altitude ---- */
    {
        char alt_buf[16] = { 0 };
        (void)snprintf(alt_buf, sizeof(alt_buf), "ALT %dM", (int)alt->current_altitude_m);
        const int alt_scale = 5;
        const int alt_w = host_sim_measure_text(alt_buf, alt_scale);
        const int alt_y = 310;
        host_sim_draw_text(canvas, alt_buf, cx - alt_w / 2, alt_y, alt_scale, text_r, text_g,
                           text_b);
    }

    /* ---- Ascent / descent row ---- */
    {
        char asc_buf[12] = { 0 };
        char desc_buf[12] = { 0 };
        format_altitude_delta((int16_t)alt->total_ascent_m, 1, asc_buf, sizeof(asc_buf));
        format_altitude_delta((int16_t)alt->total_descent_m, 0, desc_buf, sizeof(desc_buf));

        /* Ascent and descent side by side with a gap. */
        char combined[28] = { 0 };
        (void)snprintf(combined, sizeof(combined), "%s  %s", asc_buf, desc_buf);

        const int row_scale = 3;
        const int row_w = host_sim_measure_text(combined, row_scale);
        const int row_y = 360;
        host_sim_draw_text(canvas, combined, cx - row_w / 2, row_y, row_scale, text_r, text_g,
                           text_b);
    }

    host_sim_canvas_apply_round_mask(canvas);
}
