/*
 * screen_fuel.c — renders the fuel estimate screen onto the round 466x466 panel.
 *
 * Layout:
 *   - Background: dark navy in day mode, black in night mode.
 *   - Hero: vertical fuel bar (left side) that fills from bottom to top,
 *     with the tank percentage overlaid as large text.
 *   - Estimated range: large text on the right: "175 KM".
 *   - Consumption: small text: "38 ML/KM" (mL/km matches the wire format).
 *   - Fuel remaining: small text: "6.5 L" (mL converted to L with 1 decimal).
 *   - Unknown values (0xFFFF): "-- KM", "-- ML/KM", "-- L".
 *   - Low fuel warning: tank_percent <= 15 renders percentage in warning color
 *     (yellow in day mode, bright red in night mode).
 *   - Night mode: red palette.
 */
#include "host_sim/renderer.h"
#include "text_draw.h"
#include "fuel_layout.h"

#include <stdio.h>
#include <string.h>

#include "ble_protocol.h"

/* Warning threshold for low fuel. */
#define LOW_FUEL_THRESHOLD 15

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

static void fill_rect(host_sim_canvas_t *canvas, int x, int y, int w, int h, uint8_t r, uint8_t g,
                      uint8_t b)
{
    for (int yy = y; yy < y + h; ++yy) {
        for (int xx = x; xx < x + w; ++xx) {
            put_pixel(canvas, xx, yy, r, g, b);
        }
    }
}

void host_sim_render_fuel(host_sim_canvas_t *canvas, const ble_fuel_data_t *fuel,
                          uint8_t header_flags)
{
    const int night = (header_flags & BLE_FLAG_NIGHT_MODE) != 0U;
    if (night) {
        host_sim_canvas_fill(canvas, 0, 0, 0);
    } else {
        host_sim_canvas_fill(canvas, 0x0A, 0x1C, 0x3A);
    }

    const uint8_t text_r = night ? 0x88U : 0xFFU;
    const uint8_t text_g = night ? 0x11U : 0xFFU;
    const uint8_t text_b = night ? 0x11U : 0xFFU;

    /* Warning color for low fuel */
    const int low_fuel = fuel->tank_percent <= LOW_FUEL_THRESHOLD;
    uint8_t warn_r, warn_g, warn_b;
    if (night) {
        warn_r = 0xFFU;
        warn_g = 0x33U;
        warn_b = 0x33U; /* bright red */
    } else {
        warn_r = 0xFFU;
        warn_g = 0xD7U;
        warn_b = 0x00U; /* yellow */
    }

    const int cx = canvas->width / 2;

    /* ---- Fuel bar (vertical, left side) ---- */
    const int bar_x = 100;
    const int bar_y = 100;
    const int bar_w = 50;
    const int bar_h = 260;
    const int filled = fuel_bar_fill(fuel->tank_percent, bar_h);

    /* Bar outline (border) */
    const uint8_t border_r = night ? 0x55U : 0x88U;
    const uint8_t border_g = night ? 0x00U : 0x88U;
    const uint8_t border_b = night ? 0x00U : 0x88U;
    fill_rect(canvas, bar_x - 2, bar_y - 2, bar_w + 4, bar_h + 4, border_r, border_g, border_b);

    /* Bar background (empty portion) */
    const uint8_t bg_r = night ? 0x11U : 0x22U;
    const uint8_t bg_g = night ? 0x00U : 0x22U;
    const uint8_t bg_b = night ? 0x00U : 0x33U;
    fill_rect(canvas, bar_x, bar_y, bar_w, bar_h, bg_r, bg_g, bg_b);

    /* Bar fill (from bottom) */
    uint8_t fill_r, fill_g, fill_b;
    if (low_fuel) {
        fill_r = warn_r;
        fill_g = warn_g;
        fill_b = warn_b;
    } else if (night) {
        fill_r = 0x88U;
        fill_g = 0x11U;
        fill_b = 0x11U;
    } else {
        fill_r = 0x00U;
        fill_g = 0xCCU;
        fill_b = 0x66U; /* green */
    }
    if (filled > 0) {
        fill_rect(canvas, bar_x, bar_y + bar_h - filled, bar_w, filled, fill_r, fill_g, fill_b);
    }

    /* ---- Tank percentage (hero text, overlaid on bar area) ---- */
    char pct_buf[8] = { 0 };
    format_tank_percent(fuel->tank_percent, pct_buf, sizeof(pct_buf));

    const int pct_scale = 7;
    const int pct_w = host_sim_measure_text(pct_buf, pct_scale);
    const int pct_x = bar_x + bar_w / 2 - pct_w / 2;
    const int pct_y = bar_y + bar_h / 2 - (8 * pct_scale) / 2;
    if (low_fuel) {
        host_sim_draw_text(canvas, pct_buf, pct_x, pct_y, pct_scale, warn_r, warn_g, warn_b);
    } else {
        host_sim_draw_text(canvas, pct_buf, pct_x, pct_y, pct_scale, text_r, text_g, text_b);
    }

    /* ---- Right side info panel ---- */
    const int info_x = 210;

    /* Estimated range (large) */
    char range_buf[16] = { 0 };
    format_range(fuel->estimated_range_km, range_buf, sizeof(range_buf));
    const int range_scale = 5;
    const int range_y = 140;
    host_sim_draw_text(canvas, range_buf, info_x, range_y, range_scale, text_r, text_g, text_b);

    /* Consumption (small) */
    char cons_buf[16] = { 0 };
    format_consumption(fuel->consumption_ml_per_km, cons_buf, sizeof(cons_buf));
    const int cons_scale = 3;
    const int cons_y = range_y + 8 * range_scale + 24;
    host_sim_draw_text(canvas, cons_buf, info_x, cons_y, cons_scale, text_r, text_g, text_b);

    /* Fuel remaining (small) */
    char rem_buf[16] = { 0 };
    format_fuel_remaining(fuel->fuel_remaining_ml, rem_buf, sizeof(rem_buf));
    const int rem_scale = 3;
    const int rem_y = cons_y + 8 * cons_scale + 16;
    host_sim_draw_text(canvas, rem_buf, info_x, rem_y, rem_scale, text_r, text_g, text_b);

    /* ---- "FUEL" label at bottom ---- */
    const int label_scale = 3;
    const char *label = "FUEL";
    const int label_w = host_sim_measure_text(label, label_scale);
    const int label_y = 395;
    host_sim_draw_text(canvas, label, cx - label_w / 2, label_y, label_scale, text_r, text_g,
                       text_b);

    host_sim_canvas_apply_round_mask(canvas);
}
