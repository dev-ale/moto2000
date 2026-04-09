/*
 * screen_lean_angle.c — renders the Lean Angle screen onto the round
 * 466x466 panel.
 *
 * Layout:
 *   - Background: deep navy (#0A1C3A) day, black night.
 *   - Hero element: a lean gauge arc at the top half of the canvas
 *     spanning -60° (left) to +60° (right). Tick marks every 10°,
 *     longer at every 30°. A bright needle drawn from the gauge
 *     centre to the arc indicates the current lean.
 *   - Centred digital readout below the arc: "L 25", "R 25", or "0".
 *   - Max readouts: "MAX L 58" left, "MAX R 62" right.
 *   - Confidence label "CONF 95%" along the bottom.
 *   - Night mode mirrors the compass screen palette: black bg, dim red
 *     ticks and labels.
 */
#include "host_sim/renderer.h"
#include "lean_angle_layout.h"
#include "text_draw.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ble_protocol.h"

static void put_pixel(host_sim_canvas_t *canvas, int x, int y,
                      uint8_t r, uint8_t g, uint8_t b)
{
    if (x < 0 || y < 0 || x >= canvas->width || y >= canvas->height) {
        return;
    }
    const size_t idx = ((size_t)y * (size_t)canvas->width + (size_t)x) * 3U;
    canvas->pixels[idx + 0U] = r;
    canvas->pixels[idx + 1U] = g;
    canvas->pixels[idx + 2U] = b;
}

static void draw_thick_line(host_sim_canvas_t *canvas,
                            int x0, int y0, int x1, int y1,
                            uint8_t r, uint8_t g, uint8_t b,
                            int thickness)
{
    int dx  = abs(x1 - x0);
    int sx  = x0 < x1 ? 1 : -1;
    int dy  = -abs(y1 - y0);
    int sy  = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    const int half = thickness / 2;
    for (;;) {
        for (int ty = -half; ty <= half; ++ty) {
            for (int tx = -half; tx <= half; ++tx) {
                put_pixel(canvas, x0 + tx, y0 + ty, r, g, b);
            }
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

static void draw_arc_ticks(host_sim_canvas_t *canvas,
                           int cx, int cy, int radius,
                           uint8_t r, uint8_t g, uint8_t b)
{
    /* Tick marks every 10° from -60 to +60. Longer ticks at every 30°. */
    for (int deg = -60; deg <= 60; deg += 10) {
        const int  major     = (deg % 30 == 0);
        const int  inner_r   = major ? radius - 24 : radius - 14;
        const int  thickness = major ? 4 : 2;
        int outer_x = 0, outer_y = 0;
        int inner_x = 0, inner_y = 0;
        lean_arc_needle_endpoint((int16_t)(deg * 10), cx, cy, radius,
                                 &outer_x, &outer_y);
        lean_arc_needle_endpoint((int16_t)(deg * 10), cx, cy, inner_r,
                                 &inner_x, &inner_y);
        draw_thick_line(canvas, inner_x, inner_y, outer_x, outer_y,
                        r, g, b, thickness);
    }
}

static void draw_arc_outline(host_sim_canvas_t *canvas,
                             int cx, int cy, int radius,
                             uint8_t r, uint8_t g, uint8_t b)
{
    /* Sample the arc at 1° intervals and draw a tiny dot at each
     * sample point. Cheap, deterministic, no antialiasing. */
    for (int deg10 = -600; deg10 <= 600; deg10 += 10) {
        int x = 0, y = 0;
        lean_arc_needle_endpoint((int16_t)deg10, cx, cy, radius, &x, &y);
        put_pixel(canvas, x,     y,     r, g, b);
        put_pixel(canvas, x + 1, y,     r, g, b);
        put_pixel(canvas, x,     y + 1, r, g, b);
        put_pixel(canvas, x - 1, y,     r, g, b);
        put_pixel(canvas, x,     y - 1, r, g, b);
    }
}

void host_sim_render_lean_angle(host_sim_canvas_t           *canvas,
                                const ble_lean_angle_data_t *lean,
                                uint8_t                      header_flags)
{
    const bool night = (header_flags & BLE_FLAG_NIGHT_MODE) != 0U;
    if (night) {
        host_sim_canvas_fill(canvas, 0, 0, 0);
    } else {
        host_sim_canvas_fill(canvas, 0x0A, 0x1C, 0x3A);
    }

    /* Foreground colours follow the compass screen palette so the
     * dashboard feels coherent across screens. */
    const uint8_t fg_r = night ? 0x66U : 0xFFU;
    const uint8_t fg_g = night ? 0x11U : 0xFFU;
    const uint8_t fg_b = night ? 0x11U : 0xFFU;

    const int cx = canvas->width / 2;
    /* Pivot the gauge a bit below the geometric centre so the arc tips
     * have room to breathe at the top of the canvas. */
    const int cy = canvas->height / 2 + 60;
    const int arc_radius = 200;

    draw_arc_outline(canvas, cx, cy, arc_radius, fg_r, fg_g, fg_b);
    draw_arc_ticks(canvas, cx, cy, arc_radius, fg_r, fg_g, fg_b);

    /* Needle: a thick bright line from the centre to the arc tip. The
     * needle uses a warmer accent colour so it stands out against the
     * white ticks. In night mode the needle is bright red, matching
     * the compass pointer. */
    const uint8_t needle_r = 0xFFU;
    const uint8_t needle_g = night ? 0x33U : 0x55U;
    const uint8_t needle_b = night ? 0x33U : 0x55U;
    int needle_x = 0, needle_y = 0;
    lean_arc_needle_endpoint(lean->current_lean_deg_x10, cx, cy,
                             arc_radius - 6, &needle_x, &needle_y);
    draw_thick_line(canvas, cx, cy, needle_x, needle_y,
                    needle_r, needle_g, needle_b, 6);

    /* Digital current readout: large, centred, sits below the gauge
     * pivot so it never collides with the arc. */
    char digital[16];
    (void)format_lean_digital(lean->current_lean_deg_x10, digital, sizeof(digital));
    const int digital_scale = 8;
    const int digital_h     = 8 * digital_scale;
    const int digital_w     = host_sim_measure_text(digital, digital_scale);
    const int digital_y     = cy + 30;
    host_sim_draw_text(canvas, digital,
                       cx - digital_w / 2,
                       digital_y,
                       digital_scale,
                       fg_r, fg_g, fg_b);

    /* Max readouts: small, beside the digital readout. */
    char max_left[16];
    char max_right[16];
    (void)format_max_lean(lean->max_left_lean_deg_x10, 'L', max_left, sizeof(max_left));
    (void)format_max_lean(lean->max_right_lean_deg_x10, 'R', max_right, sizeof(max_right));
    const int max_scale = 3;
    const int max_h     = 8 * max_scale;
    const int max_y     = digital_y + digital_h + 16;
    const int left_w    = host_sim_measure_text(max_left, max_scale);
    host_sim_draw_text(canvas, max_left,
                       cx - left_w - 24,
                       max_y,
                       max_scale,
                       fg_r, fg_g, fg_b);
    host_sim_draw_text(canvas, max_right,
                       cx + 24,
                       max_y,
                       max_scale,
                       fg_r, fg_g, fg_b);

    /* Confidence: bottom-centre. The font has no '%' so we suffix
     * with the literal characters that exist in the bundled bitmap. */
    char conf_buf[16];
    (void)snprintf(conf_buf, sizeof(conf_buf), "CONF %u", (unsigned)lean->confidence_percent);
    const int conf_scale = 3;
    const int conf_w     = host_sim_measure_text(conf_buf, conf_scale);
    const int conf_y     = max_y + max_h + 12;
    host_sim_draw_text(canvas, conf_buf,
                       cx - conf_w / 2,
                       conf_y,
                       conf_scale,
                       fg_r, fg_g, fg_b);

    host_sim_canvas_apply_round_mask(canvas);
}
