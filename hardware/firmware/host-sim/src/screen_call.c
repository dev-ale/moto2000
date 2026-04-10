/*
 * screen_call.c — renders the incoming call alert overlay onto the round
 * 466x466 panel.
 *
 * Layout:
 *   - Background: dark red-tinted overlay (alert priority) in day mode,
 *     black with red accents in night mode.
 *   - Phone icon glyph: a simple filled circle at top-center representing
 *     a phone icon placeholder.
 *   - State text: "INCOMING CALL" / "CONNECTED" / "ENDED" centred large.
 *   - Caller handle: centred below state text.
 *   - Initial avatar circle: a circle with the first letter of the handle.
 *   - Night mode: red palette.
 */
#include "host_sim/renderer.h"
#include "text_draw.h"
#include "call_layout.h"

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

static void fill_circle(host_sim_canvas_t *canvas, int cx, int cy, int radius, uint8_t r, uint8_t g,
                        uint8_t b)
{
    const int r2 = radius * radius;
    for (int y = cy - radius; y <= cy + radius; ++y) {
        for (int x = cx - radius; x <= cx + radius; ++x) {
            const int dx = x - cx;
            const int dy = y - cy;
            if (dx * dx + dy * dy <= r2) {
                put_pixel(canvas, x, y, r, g, b);
            }
        }
    }
}

void host_sim_render_call(host_sim_canvas_t *canvas, const ble_incoming_call_data_t *call,
                          uint8_t header_flags)
{
    const int night = (header_flags & BLE_FLAG_NIGHT_MODE) != 0U;
    const int alert = (header_flags & BLE_FLAG_ALERT) != 0U;

    /* Alert overlay uses a darker, red-tinted background */
    if (night) {
        host_sim_canvas_fill(canvas, 0x0A, 0x00, 0x00);
    } else if (alert) {
        host_sim_canvas_fill(canvas, 0x2A, 0x0A, 0x0A);
    } else {
        host_sim_canvas_fill(canvas, 0x0A, 0x1C, 0x3A);
    }

    const uint8_t text_r = night ? 0x88U : 0xFFU;
    const uint8_t text_g = night ? 0x11U : 0xFFU;
    const uint8_t text_b = night ? 0x11U : 0xFFU;

    /* Accent color for the phone icon and avatar */
    const uint8_t accent_r = night ? 0xCCU : 0x44U;
    const uint8_t accent_g = night ? 0x22U : 0xCCU;
    const uint8_t accent_b = night ? 0x22U : 0x44U;

    const int cx = canvas->width / 2;

    /* ---- Phone icon glyph (filled circle placeholder) ---- */
    const int phone_y = 120;
    const int phone_radius = 25;
    fill_circle(canvas, cx, phone_y, phone_radius, accent_r, accent_g, accent_b);

    /* Draw a "phone" character inside the circle */
    const char phone_char[] = "#";
    const int phone_scale = 4;
    const int phone_w = host_sim_measure_text(phone_char, phone_scale);
    host_sim_draw_text(canvas, phone_char, cx - phone_w / 2, phone_y - (8 * phone_scale) / 2,
                       phone_scale, text_r, text_g, text_b);

    /* ---- State text ---- */
    const char *state_label = call_state_label(call->call_state);
    const int state_scale = 4;
    const int state_w = host_sim_measure_text(state_label, state_scale);
    const int state_y = 180;
    host_sim_draw_text(canvas, state_label, cx - state_w / 2, state_y, state_scale, text_r, text_g,
                       text_b);

    /* ---- Avatar circle with initial ---- */
    const int avatar_y = 270;
    const int avatar_radius = 35;
    fill_circle(canvas, cx, avatar_y, avatar_radius, accent_r, accent_g, accent_b);

    char initial_buf[2] = { call_avatar_initial(call->caller_handle), '\0' };
    const int initial_scale = 6;
    const int initial_w = host_sim_measure_text(initial_buf, initial_scale);
    host_sim_draw_text(canvas, initial_buf, cx - initial_w / 2, avatar_y - (8 * initial_scale) / 2,
                       initial_scale, text_r, text_g, text_b);

    /* ---- Caller handle ---- */
    const int handle_scale = 3;
    const int handle_w = host_sim_measure_text(call->caller_handle, handle_scale);
    const int handle_y = avatar_y + avatar_radius + 20;
    host_sim_draw_text(canvas, call->caller_handle, cx - handle_w / 2, handle_y, handle_scale,
                       text_r, text_g, text_b);

    host_sim_canvas_apply_round_mask(canvas);
}
