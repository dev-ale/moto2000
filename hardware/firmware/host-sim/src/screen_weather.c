/*
 * screen_weather.c — renders the weather screen onto the round 466x466 panel.
 *
 * Layout:
 *   - Background: navy in day mode, black in night mode (matching the
 *     compass/clock/lean family).
 *   - Large pixel-art condition glyph centered horizontally at the top of
 *     the panel. Each glyph is a small hand-authored bitmap defined below
 *     (sun, cloud, rain lines, snowflake, fog lines, lightning bolt).
 *     All glyphs share a 64x48 bounding box; see weather_layout.c.
 *   - Hero temperature text in the middle (e.g. "22^" / "-3^"). The
 *     caret `^` is mapped by the embedded font to a degree glyph added
 *     in Slice 7.
 *   - "H 25  L 13" high/low line below the hero.
 *   - Uppercased location at the bottom, truncated to 16 characters.
 *
 * Night mode switches the palette to red-shifted pixels. Pure C software
 * rasteriser, no LVGL — matches the rest of the slice-1.5b host-sim
 * backend.
 */
#include "host_sim/renderer.h"
#include "text_draw.h"
#include "weather_layout.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ble_protocol.h"

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} rgb_t;

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

static void fill_rect(host_sim_canvas_t *canvas,
                      int x, int y, int w, int h,
                      rgb_t c)
{
    for (int yy = y; yy < y + h; ++yy) {
        for (int xx = x; xx < x + w; ++xx) {
            put_pixel(canvas, xx, yy, c.r, c.g, c.b);
        }
    }
}

static void fill_disc(host_sim_canvas_t *canvas,
                      int cx, int cy, int radius,
                      rgb_t c)
{
    const int r2 = radius * radius;
    for (int y = cy - radius; y <= cy + radius; ++y) {
        for (int x = cx - radius; x <= cx + radius; ++x) {
            const int dx = x - cx;
            const int dy = y - cy;
            if (dx * dx + dy * dy <= r2) {
                put_pixel(canvas, x, y, c.r, c.g, c.b);
            }
        }
    }
}

/* ------------------------------------------------------------------ */
/* Condition glyphs                                                    */
/* ------------------------------------------------------------------ */
/*
 * Every glyph is drawn relative to an anchor (ax, ay) which represents
 * the centre of the 64x48 bounding box. Drawing is done with the
 * primitives above so there are no external assets.
 */

static void draw_sun(host_sim_canvas_t *canvas, int ax, int ay, rgb_t c)
{
    /* Sun body + 8 rays. */
    fill_disc(canvas, ax, ay, 14, c);
    /* Rays: 8 stubby rectangles around the body. */
    fill_rect(canvas, ax - 2, ay - 24, 4, 8, c);
    fill_rect(canvas, ax - 2, ay + 16, 4, 8, c);
    fill_rect(canvas, ax - 24, ay - 2, 8, 4, c);
    fill_rect(canvas, ax + 16, ay - 2, 8, 4, c);
    /* Diagonal rays as tiny squares. */
    for (int i = 0; i < 6; ++i) {
        put_pixel(canvas, ax + 15 + i, ay - 15 - i, c.r, c.g, c.b);
        put_pixel(canvas, ax + 16 + i, ay - 15 - i, c.r, c.g, c.b);
        put_pixel(canvas, ax - 15 - i, ay - 15 - i, c.r, c.g, c.b);
        put_pixel(canvas, ax - 16 - i, ay - 15 - i, c.r, c.g, c.b);
        put_pixel(canvas, ax + 15 + i, ay + 15 + i, c.r, c.g, c.b);
        put_pixel(canvas, ax + 16 + i, ay + 15 + i, c.r, c.g, c.b);
        put_pixel(canvas, ax - 15 - i, ay + 15 + i, c.r, c.g, c.b);
        put_pixel(canvas, ax - 16 - i, ay + 15 + i, c.r, c.g, c.b);
    }
}

static void draw_cloud_shape(host_sim_canvas_t *canvas, int ax, int ay, rgb_t c)
{
    /* A cloud is two overlapping discs plus a flat base. */
    fill_disc(canvas, ax - 10, ay, 12, c);
    fill_disc(canvas, ax + 10, ay, 12, c);
    fill_disc(canvas, ax, ay - 8, 14, c);
    fill_rect(canvas, ax - 22, ay, 44, 10, c);
}

static void draw_cloudy(host_sim_canvas_t *canvas, int ax, int ay, rgb_t c)
{
    draw_cloud_shape(canvas, ax, ay - 4, c);
}

static void draw_rain(host_sim_canvas_t *canvas, int ax, int ay, rgb_t cloud, rgb_t drop)
{
    draw_cloud_shape(canvas, ax, ay - 10, cloud);
    /* Three diagonal rain streaks below the cloud. */
    for (int i = 0; i < 3; ++i) {
        const int sx = ax - 16 + i * 16;
        for (int k = 0; k < 10; ++k) {
            put_pixel(canvas, sx + k / 2, ay + 8 + k, drop.r, drop.g, drop.b);
            put_pixel(canvas, sx + k / 2 + 1, ay + 8 + k, drop.r, drop.g, drop.b);
        }
    }
}

static void draw_snow(host_sim_canvas_t *canvas, int ax, int ay, rgb_t c)
{
    /* Six-armed snowflake centered on (ax, ay). */
    fill_rect(canvas, ax - 24, ay - 2, 48, 4, c);
    fill_rect(canvas, ax - 2, ay - 24, 4, 48, c);
    /* Diagonal arms: thick lines using put_pixel loops. */
    for (int i = -20; i <= 20; ++i) {
        put_pixel(canvas, ax + i, ay + i, c.r, c.g, c.b);
        put_pixel(canvas, ax + i + 1, ay + i, c.r, c.g, c.b);
        put_pixel(canvas, ax + i, ay - i, c.r, c.g, c.b);
        put_pixel(canvas, ax + i + 1, ay - i, c.r, c.g, c.b);
    }
    /* Arrow tips on the cardinal arms. */
    fill_rect(canvas, ax - 6, ay - 24, 12, 2, c);
    fill_rect(canvas, ax - 6, ay + 22, 12, 2, c);
    fill_rect(canvas, ax - 24, ay - 6, 2, 12, c);
    fill_rect(canvas, ax + 22, ay - 6, 2, 12, c);
}

static void draw_fog(host_sim_canvas_t *canvas, int ax, int ay, rgb_t c)
{
    /* Four horizontal fog bars of varying length. */
    fill_rect(canvas, ax - 28, ay - 16, 56, 5, c);
    fill_rect(canvas, ax - 22, ay - 4,  48, 5, c);
    fill_rect(canvas, ax - 28, ay + 8,  56, 5, c);
    fill_rect(canvas, ax - 18, ay + 20, 44, 5, c);
}

static void draw_thunderstorm(host_sim_canvas_t *canvas, int ax, int ay, rgb_t cloud, rgb_t bolt)
{
    draw_cloud_shape(canvas, ax, ay - 12, cloud);
    /* A blocky lightning bolt below the cloud. */
    const int bx = ax - 4;
    const int by = ay + 8;
    fill_rect(canvas, bx + 4, by,      8, 6, bolt);
    fill_rect(canvas, bx,     by + 4,  12, 6, bolt);
    fill_rect(canvas, bx - 2, by + 8,  10, 6, bolt);
    fill_rect(canvas, bx + 2, by + 12, 12, 4, bolt);
    fill_rect(canvas, bx + 4, by + 14, 4, 12, bolt);
}

static void draw_condition_glyph(host_sim_canvas_t      *canvas,
                                 ble_weather_condition_t cond,
                                 int                     ax,
                                 int                     ay,
                                 bool                    night)
{
    const rgb_t day_sun    = {0xFF, 0xD1, 0x3A};
    const rgb_t day_cloud  = {0xE8, 0xEF, 0xF7};
    const rgb_t day_rain   = {0x6E, 0xB8, 0xFF};
    const rgb_t day_bolt   = {0xFF, 0xE0, 0x40};
    const rgb_t night_red  = {0x88, 0x11, 0x11};
    const rgb_t night_dim  = {0x55, 0x00, 0x00};

    const rgb_t sun_c   = night ? night_red : day_sun;
    const rgb_t cloud_c = night ? night_red : day_cloud;
    const rgb_t rain_c  = night ? night_dim : day_rain;
    const rgb_t bolt_c  = night ? night_red : day_bolt;

    switch (cond) {
        case BLE_WEATHER_CLEAR:
            draw_sun(canvas, ax, ay, sun_c);
            break;
        case BLE_WEATHER_CLOUDY:
            draw_cloudy(canvas, ax, ay, cloud_c);
            break;
        case BLE_WEATHER_RAIN:
            draw_rain(canvas, ax, ay, cloud_c, rain_c);
            break;
        case BLE_WEATHER_SNOW:
            draw_snow(canvas, ax, ay, cloud_c);
            break;
        case BLE_WEATHER_FOG:
            draw_fog(canvas, ax, ay, cloud_c);
            break;
        case BLE_WEATHER_THUNDERSTORM:
            draw_thunderstorm(canvas, ax, ay, cloud_c, bolt_c);
            break;
        default:
            break;
    }
}

/* ------------------------------------------------------------------ */

void host_sim_render_weather(host_sim_canvas_t        *canvas,
                             const ble_weather_data_t *weather,
                             uint8_t                   header_flags)
{
    const bool night = (header_flags & BLE_FLAG_NIGHT_MODE) != 0U;
    if (night) {
        host_sim_canvas_fill(canvas, 0, 0, 0);
    } else {
        host_sim_canvas_fill(canvas, 0x0A, 0x1C, 0x3A);
    }

    const uint8_t text_r = night ? 0x88U : 0xFFU;
    const uint8_t text_g = night ? 0x11U : 0xFFU;
    const uint8_t text_b = night ? 0x11U : 0xFFU;

    const int cx = canvas->width  / 2;

    /* Glyph: centered horizontally, anchored ~30% from the top. */
    const int glyph_ay = 150;
    draw_condition_glyph(canvas, weather->condition, cx, glyph_ay, night);

    /* Hero temperature, e.g. "22^" or "-3^". The caret maps to the
     * degree glyph in font8x8.h. */
    char temp_buf[8] = {0};
    host_sim_weather_format_temperature(weather->temperature_celsius_x10,
                                        temp_buf, sizeof(temp_buf));
    char hero[16] = {0};
    (void)snprintf(hero, sizeof(hero), "%s^", temp_buf);

    const int hero_scale = 8;
    const int hero_w     = host_sim_measure_text(hero, hero_scale);
    const int hero_h     = 8 * hero_scale;
    const int hero_y     = 220;
    host_sim_draw_text(canvas, hero, cx - hero_w / 2, hero_y, hero_scale,
                       text_r, text_g, text_b);

    /* High/low line. */
    char hilo[16] = {0};
    host_sim_weather_format_high_low(weather->high_celsius_x10,
                                     weather->low_celsius_x10,
                                     hilo, sizeof(hilo));
    const int hilo_scale = 3;
    const int hilo_w     = host_sim_measure_text(hilo, hilo_scale);
    const int hilo_y     = hero_y + hero_h + 16;
    host_sim_draw_text(canvas, hilo, cx - hilo_w / 2, hilo_y, hilo_scale,
                       text_r, text_g, text_b);

    /* Location name at the bottom. */
    char loc[WEATHER_LAYOUT_MAX_LOCATION_CHARS + 1] = {0};
    host_sim_weather_uppercase_location(weather->location_name, loc, sizeof(loc));
    const int loc_scale = 3;
    const int loc_w     = host_sim_measure_text(loc, loc_scale);
    const int loc_y     = 390;
    host_sim_draw_text(canvas, loc, cx - loc_w / 2, loc_y, loc_scale,
                       text_r, text_g, text_b);

    host_sim_canvas_apply_round_mask(canvas);
}
