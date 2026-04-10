/*
 * screen_blitzer.c — renders the blitzer (speed camera) alert overlay onto
 * the round 466x466 panel.
 *
 * Layout:
 *   - Background: amber-tinted in day mode (alert urgency), red in night mode.
 *   - Warning icon: large "!" character in a triangle placeholder at the top.
 *   - Distance: hero text — "500M" or "1.2KM", large and centred.
 *   - Speed limit: "LIMIT 80" or "LIMIT --" centred below distance.
 *   - Current speed: "72 KM/H". Red/bright if speeding.
 *   - Camera type: small text at the bottom — "FIXED", "MOBILE", etc.
 *   - Night mode: red palette, warning icon stays red.
 */
#include "host_sim/renderer.h"
#include "text_draw.h"
#include "blitzer_layout.h"

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

/* Draw a filled triangle (warning icon placeholder). */
static void draw_warning_triangle(host_sim_canvas_t *canvas, int cx, int top_y, int size, uint8_t r,
                                  uint8_t g, uint8_t b)
{
    /* Simple isoceles triangle pointing up. */
    for (int row = 0; row < size; ++row) {
        int half_width = (row * size) / (size > 0 ? size : 1);
        int y = top_y + row;
        for (int dx = -half_width; dx <= half_width; ++dx) {
            put_pixel(canvas, cx + dx, y, r, g, b);
        }
    }
}

void host_sim_render_blitzer(host_sim_canvas_t *canvas, const ble_blitzer_data_t *blitzer,
                             uint8_t header_flags)
{
    const int night = (header_flags & BLE_FLAG_NIGHT_MODE) != 0U;

    /* Alert overlay: amber tint in day, dark red in night */
    if (night) {
        host_sim_canvas_fill(canvas, 0x0A, 0x00, 0x00);
    } else {
        host_sim_canvas_fill(canvas, 0x2A, 0x1A, 0x00);
    }

    /* Text colours */
    const uint8_t text_r = night ? 0x88U : 0xFFU;
    const uint8_t text_g = night ? 0x11U : 0xFFU;
    const uint8_t text_b = night ? 0x11U : 0xFFU;

    /* Warning colours (amber day, red night) */
    const uint8_t warn_r = night ? 0xCCU : 0xFFU;
    const uint8_t warn_g = night ? 0x22U : 0xAAU;
    const uint8_t warn_b = night ? 0x22U : 0x00U;

    /* Speeding colour (red in both modes) */
    const uint8_t speed_r = 0xFFU;
    const uint8_t speed_g = 0x22U;
    const uint8_t speed_b = 0x22U;

    const int cx = canvas->width / 2;

    /* ---- Warning triangle icon ---- */
    draw_warning_triangle(canvas, cx, 60, 48, warn_r, warn_g, warn_b);

    /* "!" inside the triangle */
    const char exclaim[] = "!";
    const int ex_scale = 4;
    const int ex_w = host_sim_measure_text(exclaim, ex_scale);
    host_sim_draw_text(canvas, exclaim, cx - ex_w / 2, 60 + 12, ex_scale, night ? 0x00U : 0x00U,
                       night ? 0x00U : 0x00U, night ? 0x00U : 0x00U);

    /* ---- Distance (hero text) ---- */
    char dist_buf[16];
    format_blitzer_distance(blitzer->distance_meters, dist_buf, sizeof(dist_buf));
    const int dist_scale = 6;
    const int dist_w = host_sim_measure_text(dist_buf, dist_scale);
    const int dist_y = 140;
    host_sim_draw_text(canvas, dist_buf, cx - dist_w / 2, dist_y, dist_scale, text_r, text_g,
                       text_b);

    /* ---- Speed limit ---- */
    char limit_buf[16];
    format_speed_limit(blitzer->speed_limit_kmh, limit_buf, sizeof(limit_buf));
    const int limit_scale = 4;
    const int limit_w = host_sim_measure_text(limit_buf, limit_scale);
    const int limit_y = dist_y + dist_scale * 8 + 16;
    host_sim_draw_text(canvas, limit_buf, cx - limit_w / 2, limit_y, limit_scale, text_r, text_g,
                       text_b);

    /* ---- Current speed ---- */
    char speed_buf[16];
    unsigned speed_whole = blitzer->current_speed_kmh_x10 / 10U;
    snprintf(speed_buf, sizeof(speed_buf), "%u KM/H", speed_whole);
    const int speed_scale = 3;
    const int speed_w = host_sim_measure_text(speed_buf, speed_scale);
    const int speed_y = limit_y + limit_scale * 8 + 16;

    const bool speeding = is_speeding(blitzer->current_speed_kmh_x10, blitzer->speed_limit_kmh);
    if (speeding) {
        host_sim_draw_text(canvas, speed_buf, cx - speed_w / 2, speed_y, speed_scale, speed_r,
                           speed_g, speed_b);
    } else {
        host_sim_draw_text(canvas, speed_buf, cx - speed_w / 2, speed_y, speed_scale, text_r,
                           text_g, text_b);
    }

    /* ---- Camera type ---- */
    char type_buf[16];
    format_camera_type((uint8_t)blitzer->camera_type, type_buf, sizeof(type_buf));
    const int type_scale = 2;
    const int type_w = host_sim_measure_text(type_buf, type_scale);
    const int type_y = speed_y + speed_scale * 8 + 20;
    host_sim_draw_text(canvas, type_buf, cx - type_w / 2, type_y, type_scale, warn_r, warn_g,
                       warn_b);

    host_sim_canvas_apply_round_mask(canvas);
}
