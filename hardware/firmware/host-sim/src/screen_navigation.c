/*
 * screen_navigation.c — renders the navigation (turn-by-turn) screen on
 * the round 466×466 panel.
 *
 * Layout:
 *   - Big hero arrow in the top-centre region, derived from the
 *     nav_data_t maneuver enum via host_sim_nav_arrow_shape(). All
 *     shapes are composed of axis-aligned rectangles so there is no
 *     anti-aliasing, no new font engine, and snapshots stay stable.
 *   - Large distance-to-maneuver readout below the arrow
 *     (e.g. "320M" or "0.5KM").
 *   - Street name on a thin line below the distance, uppercased and
 *     clamped to 18 characters so it fits inside the safe area.
 *   - Small status line at the bottom: "ETA 18M  REM 7.4KM".
 *   - Night mode uses a dim amber palette matching the clock/compass.
 *
 * All text and distance formatting lives in navigation_layout.c so
 * Unity tests can exercise it without touching the canvas.
 */
#include "host_sim/renderer.h"
#include "host_sim/navigation_layout.h"
#include "text_draw.h"

#include <string.h>

#include "ble_protocol.h"

/* ---------------------------------------------------------------------------
 * Local drawing primitives. Kept static to this translation unit so we
 * don't have to extend text_draw.h for a one-off use case.
 * ------------------------------------------------------------------------- */

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

static void center_text(host_sim_canvas_t *canvas, const char *text, int y, int scale, uint8_t r,
                        uint8_t g, uint8_t b)
{
    const int w = host_sim_measure_text(text, scale);
    const int x = (canvas->width - w) / 2;
    host_sim_draw_text(canvas, text, x, y, scale, r, g, b);
}

/* ---------------------------------------------------------------------------
 * Arrow glyphs. All coordinates are in absolute canvas space; callers
 * pass the centre point of the arrow region and a colour.
 *
 * The arrow visual language matches typical moto navigation HUDs:
 *   - Straight: vertical shaft + upward triangle head (stepped blocks).
 *   - Left / right: horizontal shaft + side-pointing head.
 *   - U-turn: half-loop + downward head.
 *   - Arrive: solid disc (approximated by a filled square) with a ring.
 *   - Roundabout: ring + arrow pointing out.
 *   - Fork left/right: diagonal stub off a vertical shaft.
 * ------------------------------------------------------------------------- */

static void draw_arrow_straight(host_sim_canvas_t *canvas, int cx, int cy, uint8_t r, uint8_t g,
                                uint8_t b)
{
    /* Vertical shaft: 24 wide, 100 tall, centred at (cx, cy). */
    fill_rect(canvas, cx - 12, cy - 30, 24, 80, r, g, b);
    /* Stepped triangle head, 10 rows high, widening towards the base. */
    for (int i = 0; i < 10; ++i) {
        const int w = 12 + i * 6; /* 12, 18, 24, ... */
        fill_rect(canvas, cx - w, cy - 50 + i * 2, w * 2, 2, r, g, b);
    }
}

static void draw_arrow_horizontal(host_sim_canvas_t *canvas, int cx, int cy,
                                  int dir, /* -1 = left, +1 = right */
                                  uint8_t r, uint8_t g, uint8_t b)
{
    /* Horizontal shaft centred on (cx, cy): 80 wide, 24 tall. */
    fill_rect(canvas, cx - 40, cy - 12, 80, 24, r, g, b);
    /* Stepped triangle head on the leading side: widest adjacent to the
     * shaft, narrowing to a single pixel column at the tip. 10 columns
     * of 2px each → 20px-long head, height 60 → 12. */
    for (int i = 0; i < 10; ++i) {
        const int h = 60 - i * 6;
        const int x = (dir > 0) ? (cx + 40 + i * 2) : (cx - 40 - (i + 1) * 2);
        fill_rect(canvas, x, cy - h, 2, h * 2, r, g, b);
    }
}

static void draw_arrow_u_turn(host_sim_canvas_t *canvas, int cx, int cy, int dir, uint8_t r,
                              uint8_t g, uint8_t b)
{
    /* Right shaft up, curve across the top, left shaft down + head. */
    const int side = dir > 0 ? 1 : -1;
    const int shaft_top = cy - 50;
    fill_rect(canvas, cx + side * 20 - 6, shaft_top, 12, 60, r, g, b);
    fill_rect(canvas, cx - 26, shaft_top, 52, 12, r, g, b);
    fill_rect(canvas, cx - side * 20 - 6, shaft_top, 12, 80, r, g, b);
    /* Downward triangle head at the end of the left shaft. */
    for (int i = 0; i < 10; ++i) {
        const int w = 12 + i * 4;
        fill_rect(canvas, cx - side * 20 - w, cy + 30 - i * 2, w * 2, 2, r, g, b);
    }
}

static void draw_arrow_arrive(host_sim_canvas_t *canvas, int cx, int cy, uint8_t r, uint8_t g,
                              uint8_t b)
{
    /* Concentric squares → "destination pin" silhouette. */
    fill_rect(canvas, cx - 40, cy - 40, 80, 80, r, g, b);
    fill_rect(canvas, cx - 28, cy - 28, 56, 56, 0, 0, 0);
    fill_rect(canvas, cx - 16, cy - 16, 32, 32, r, g, b);
}

static void draw_arrow_roundabout(host_sim_canvas_t *canvas, int cx, int cy, uint8_t r, uint8_t g,
                                  uint8_t b)
{
    /* Stepped ring: outer square outline. */
    fill_rect(canvas, cx - 44, cy - 44, 88, 8, r, g, b);
    fill_rect(canvas, cx - 44, cy + 36, 88, 8, r, g, b);
    fill_rect(canvas, cx - 44, cy - 44, 8, 88, r, g, b);
    fill_rect(canvas, cx + 36, cy - 44, 8, 88, r, g, b);
    /* Small upward arrow inside to indicate "exit". */
    fill_rect(canvas, cx - 4, cy - 20, 8, 40, r, g, b);
    for (int i = 0; i < 6; ++i) {
        const int w = 6 + i * 3;
        fill_rect(canvas, cx - w, cy - 28 + i * 2, w * 2, 2, r, g, b);
    }
}

static void draw_arrow_fork(host_sim_canvas_t *canvas, int cx, int cy, int dir, uint8_t r,
                            uint8_t g, uint8_t b)
{
    /* Main shaft. */
    fill_rect(canvas, cx - 8, cy - 10, 16, 60, r, g, b);
    /* Angled branch: approximate with two stacked rectangles. */
    const int side = dir > 0 ? 1 : -1;
    fill_rect(canvas, cx + side * 4, cy - 30, 16, 8, r, g, b);
    fill_rect(canvas, cx + side * 18, cy - 44, 16, 8, r, g, b);
    /* Small head on the branch. */
    for (int i = 0; i < 6; ++i) {
        const int w = 4 + i * 3;
        fill_rect(canvas, cx + side * 26 - w, cy - 58 + i * 2, w * 2, 2, r, g, b);
    }
}

static void draw_arrow(host_sim_canvas_t *canvas, host_sim_arrow_shape_t shape, int cx, int cy,
                       uint8_t r, uint8_t g, uint8_t b)
{
    switch (shape) {
    case HOST_SIM_ARROW_STRAIGHT:
        draw_arrow_straight(canvas, cx, cy, r, g, b);
        return;
    case HOST_SIM_ARROW_LEFT:
        draw_arrow_horizontal(canvas, cx, cy, -1, r, g, b);
        return;
    case HOST_SIM_ARROW_RIGHT:
        draw_arrow_horizontal(canvas, cx, cy, +1, r, g, b);
        return;
    case HOST_SIM_ARROW_U_TURN_LEFT:
        draw_arrow_u_turn(canvas, cx, cy, -1, r, g, b);
        return;
    case HOST_SIM_ARROW_U_TURN_RIGHT:
        draw_arrow_u_turn(canvas, cx, cy, +1, r, g, b);
        return;
    case HOST_SIM_ARROW_ROUNDABOUT:
        draw_arrow_roundabout(canvas, cx, cy, r, g, b);
        return;
    case HOST_SIM_ARROW_ARRIVE:
        draw_arrow_arrive(canvas, cx, cy, r, g, b);
        return;
    case HOST_SIM_ARROW_FORK_LEFT:
        draw_arrow_fork(canvas, cx, cy, -1, r, g, b);
        return;
    case HOST_SIM_ARROW_FORK_RIGHT:
        draw_arrow_fork(canvas, cx, cy, +1, r, g, b);
        return;
    }
}

/* ---------------------------------------------------------------------------
 * Public entry point.
 * ------------------------------------------------------------------------- */

void host_sim_render_navigation(host_sim_canvas_t *canvas, const ble_nav_data_t *nav, uint8_t flags)
{
    const bool night = (flags & BLE_FLAG_NIGHT_MODE) != 0U;
    if (night) {
        host_sim_canvas_fill(canvas, 0, 0, 0);
    } else {
        host_sim_canvas_fill(canvas, 0x08, 0x14, 0x24);
    }

    const uint8_t fg_r = 0xFFU;
    const uint8_t fg_g = night ? 0x33U : 0xFFU;
    const uint8_t fg_b = night ? 0x33U : 0xFFU;
    const uint8_t dim_r = night ? 0x66U : 0x99U;
    const uint8_t dim_g = night ? 0x22U : 0x99U;
    const uint8_t dim_b = night ? 0x22U : 0x99U;

    /* Hero arrow at the top-centre of the canvas. */
    const int arrow_cx = canvas->width / 2;
    const int arrow_cy = 150;
    const host_sim_arrow_shape_t shape = host_sim_nav_arrow_shape(nav->maneuver);
    draw_arrow(canvas, shape, arrow_cx, arrow_cy, fg_r, fg_g, fg_b);

    /* Distance readout: large, just below the arrow. */
    char dist_buf[16];
    (void)host_sim_nav_format_distance(nav->distance_to_maneuver_m, dist_buf, sizeof(dist_buf));
    center_text(canvas, dist_buf, 225, 7, fg_r, fg_g, fg_b);

    /* Street name: uppercased, clamped to fit the safe area (≤ 18 chars). */
    char street_buf[20];
    host_sim_nav_uppercase_clamp(nav->street_name, street_buf, sizeof(street_buf));
    center_text(canvas, street_buf, 300, 3, fg_r, fg_g, fg_b);

    /* ETA + remaining distance line at the bottom of the safe area. */
    char eta_buf[40];
    (void)host_sim_nav_format_eta_line(nav->eta_minutes, nav->remaining_km_x10, eta_buf,
                                       sizeof(eta_buf));
    center_text(canvas, eta_buf, 360, 2, dim_r, dim_g, dim_b);

    host_sim_canvas_apply_round_mask(canvas);
}
