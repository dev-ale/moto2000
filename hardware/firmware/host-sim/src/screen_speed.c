/*
 * screen_speed.c — renders the Speed + Heading screen onto the round
 * 466x466 panel.
 *
 * Layout:
 *   - Background: deep navy (#0A1C3A) day, black night.
 *   - Hero speed: 3 chars, scale 12 (96px tall), upper-centre. Single-
 *     digit speeds are space-padded so the layout does not jitter.
 *   - "KM/H" unit label, muted, directly below the hero digits.
 *   - Heading block: cardinal letter + 3-digit degrees ("N 042") on the
 *     upper-right safe area, plus a short arrow drawn from a small
 *     reference centre to an endpoint projected via the shared
 *     heading_arrow_endpoint helper in speed_layout.
 *   - Altitude "ALT <n>M" bottom-left, scale 3, muted.
 *   - Temperature "T <n>C" bottom-right, scale 3, muted. The embedded
 *     8x8 font has no degree (°) glyph, so we deliberately render a
 *     plain 'C' prefixed with 'T '. Document choice here per spec.
 *   - Night mode: black bg + red-shifted foreground matching clock
 *     night screen colours.
 */
#include "host_sim/renderer.h"
#include "host_sim/speed_layout.h"
#include "text_draw.h"

#include <stdio.h>
#include <string.h>

#include "ble_protocol.h"

static void put_pixel_safe(host_sim_canvas_t *canvas,
                           int                x,
                           int                y,
                           uint8_t            r,
                           uint8_t            g,
                           uint8_t            b)
{
    if (x < 0 || y < 0 || x >= canvas->width || y >= canvas->height) {
        return;
    }
    const size_t idx = ((size_t)y * (size_t)canvas->width + (size_t)x) * 3U;
    canvas->pixels[idx + 0U] = r;
    canvas->pixels[idx + 1U] = g;
    canvas->pixels[idx + 2U] = b;
}

static void draw_fat_line(host_sim_canvas_t *canvas,
                          int x0, int y0, int x1, int y1,
                          int thickness,
                          uint8_t r, uint8_t g, uint8_t b)
{
    /* Bresenham with a square brush of side `thickness`. */
    int dx  =  (x1 > x0) ? (x1 - x0) : (x0 - x1);
    int dy  = -((y1 > y0) ? (y1 - y0) : (y0 - y1));
    int sx  = (x0 < x1) ? 1 : -1;
    int sy  = (y0 < y1) ? 1 : -1;
    int err = dx + dy;
    int x = x0;
    int y = y0;
    const int half = thickness / 2;
    for (;;) {
        for (int ty = -half; ty <= half; ++ty) {
            for (int tx = -half; tx <= half; ++tx) {
                put_pixel_safe(canvas, x + tx, y + ty, r, g, b);
            }
        }
        if (x == x1 && y == y1) {
            break;
        }
        const int e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x   += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y   += sy;
        }
    }
}

void host_sim_render_speed(host_sim_canvas_t              *canvas,
                           const ble_speed_heading_data_t *data,
                           uint8_t                         flags)
{
    const bool night = (flags & BLE_FLAG_NIGHT_MODE) != 0U;
    if (night) {
        host_sim_canvas_fill(canvas, 0, 0, 0);
    } else {
        host_sim_canvas_fill(canvas, 0x0A, 0x1C, 0x3A);
    }

    const uint8_t fg_r    = night ? 0xFFU : 0xFFU;
    const uint8_t fg_g    = night ? 0x33U : 0xFFU;
    const uint8_t fg_b    = night ? 0x33U : 0xFFU;
    const uint8_t muted_r = night ? 0xAAU : 0x88U;
    const uint8_t muted_g = night ? 0x22U : 0x99U;
    const uint8_t muted_b = night ? 0x22U : 0xAAU;
    const uint8_t accent_r = night ? 0xFFU : 0x66U;
    const uint8_t accent_g = night ? 0x55U : 0xCCU;
    const uint8_t accent_b = night ? 0x55U : 0xFFU;

    /* ---------------- hero speed digits ---------------- */
    char speed_buf[4];
    (void)host_sim_format_speed_kmh(data->speed_kmh_x10,
                                    speed_buf,
                                    sizeof(speed_buf));
    /* Skip leading spaces for visual centering — the space padding in
     * the format function is there to keep downstream logic stable,
     * but we centre the visible glyphs so short readouts (0, stationary)
     * do not appear off-centre inside the circular mask. */
    const char *speed_visible = speed_buf;
    while (*speed_visible == ' ') {
        ++speed_visible;
    }
    const int speed_scale = 12;
    int speed_x = 0;
    int speed_y = 0;
    host_sim_speed_digit_origin(canvas->width,
                                canvas->height,
                                (int)strlen(speed_visible),
                                speed_scale,
                                &speed_x,
                                &speed_y);
    /* Push down a bit so the heading block at the top has breathing room. */
    speed_y += 30;
    host_sim_draw_text(canvas, speed_visible, speed_x, speed_y,
                       speed_scale, fg_r, fg_g, fg_b);

    /* ---------------- unit label ---------------- */
    const char *unit = "KM/H";
    const int   unit_scale = 4;
    const int   unit_w = host_sim_measure_text(unit, unit_scale);
    const int   unit_x = (canvas->width - unit_w) / 2;
    const int   unit_y = speed_y + 8 * speed_scale + 16;
    host_sim_draw_text(canvas, unit, unit_x, unit_y, unit_scale,
                       muted_r, muted_g, muted_b);

    /* ---------------- heading block (upper-right) ---------------- */
    char head_buf[8];
    (void)host_sim_format_heading_label(data->heading_deg_x10,
                                        head_buf,
                                        sizeof(head_buf));
    const int head_scale = 2;
    const int head_w = host_sim_measure_text(head_buf, head_scale);
    const int head_x = canvas->width / 2 - head_w / 2;
    const int head_y = 105;
    host_sim_draw_text(canvas, head_buf, head_x, head_y, head_scale,
                       accent_r, accent_g, accent_b);

    /* Tiny compass arrow centred horizontally above the heading label. */
    const int arrow_cx  = canvas->width / 2;
    const int arrow_cy  = 70;
    const int arrow_len = 14;
    int arrow_tip_x = 0;
    int arrow_tip_y = 0;
    host_sim_heading_arrow_endpoint(data->heading_deg_x10,
                                    arrow_cx,
                                    arrow_cy,
                                    arrow_len,
                                    &arrow_tip_x,
                                    &arrow_tip_y);
    draw_fat_line(canvas,
                  arrow_cx, arrow_cy,
                  arrow_tip_x, arrow_tip_y,
                  4,
                  accent_r, accent_g, accent_b);

    /* ---------------- altitude (bottom-left) ---------------- */
    char alt_buf[16];
    (void)host_sim_format_altitude_label(data->altitude_m,
                                         alt_buf, sizeof(alt_buf));
    const int alt_scale = 3;
    const int alt_x     = 60;
    const int alt_y     = canvas->height - 8 * alt_scale - 80;
    host_sim_draw_text(canvas, alt_buf, alt_x, alt_y, alt_scale,
                       muted_r, muted_g, muted_b);

    /* ---------------- temperature (bottom-right) ---------------- */
    char temp_buf[16];
    (void)host_sim_format_temperature_label(data->temperature_celsius_x10,
                                            temp_buf, sizeof(temp_buf));
    const int temp_scale = 3;
    const int temp_w = host_sim_measure_text(temp_buf, temp_scale);
    const int temp_x = canvas->width - temp_w - 60;
    const int temp_y = canvas->height - 8 * temp_scale - 80;
    host_sim_draw_text(canvas, temp_buf, temp_x, temp_y, temp_scale,
                       muted_r, muted_g, muted_b);

    host_sim_canvas_apply_round_mask(canvas);
}
