/*
 * screen_clock.c — renders the clock screen onto the round 466x466 panel.
 *
 * Layout:
 *   - Background: black in night mode, deep blue (#0A1C3A) otherwise.
 *   - Time text centered horizontally, slightly above centre vertically.
 *     Scale 10 (80px tall) in 24h mode, scale 8 (64px) in 12h mode to fit
 *     the longer " AM" / " PM" suffix inside the circle.
 *   - Date text ("Fri 31 Jan") centered below the time at scale 3.
 *   - Tiny "24H" or "12H" badge in the top-right of the safe area.
 */
#include "host_sim/renderer.h"
#include "host_sim/time_format.h"
#include "text_draw.h"

#include <string.h>

#include "ble_protocol.h"

static void center_text(host_sim_canvas_t *canvas, const char *text, int y, int scale, uint8_t r,
                        uint8_t g, uint8_t b)
{
    const int w = host_sim_measure_text(text, scale);
    const int x = (canvas->width - w) / 2;
    host_sim_draw_text(canvas, text, x, y, scale, r, g, b);
}

void host_sim_render_clock(host_sim_canvas_t *canvas, const ble_clock_data_t *clock, uint8_t flags)
{
    const bool night = (flags & BLE_FLAG_NIGHT_MODE) != 0U;
    if (night) {
        host_sim_canvas_fill(canvas, 0, 0, 0);
    } else {
        host_sim_canvas_fill(canvas, 0x0A, 0x1C, 0x3A);
    }

    const uint8_t fg_r = night ? 0xFFU : 0xFFU;
    const uint8_t fg_g = night ? 0x33U : 0xFFU;
    const uint8_t fg_b = night ? 0x33U : 0xFFU;

    char time_buf[16];
    (void)host_sim_format_clock(clock->unix_time, clock->tz_offset_minutes, clock->is_24h, time_buf,
                                sizeof(time_buf));

    char date_buf[32];
    (void)host_sim_format_date(clock->unix_time, clock->tz_offset_minutes, date_buf,
                               sizeof(date_buf));

    const int time_scale = clock->is_24h ? 10 : 8;
    const int time_h = 8 * time_scale;
    const int date_scale = 3;
    const int date_h = 8 * date_scale;
    const int gap = 20;

    const int block_h = time_h + gap + date_h;
    const int y_time = (canvas->height - block_h) / 2;
    const int y_date = y_time + time_h + gap;

    center_text(canvas, time_buf, y_time, time_scale, fg_r, fg_g, fg_b);
    center_text(canvas, date_buf, y_date, date_scale, fg_r, fg_g, fg_b);

    /* Top badge: 24H or 12H. */
    const char *badge = clock->is_24h ? "24H" : "12H";
    const int badge_scale = 2;
    const int badge_w = host_sim_measure_text(badge, badge_scale);
    host_sim_draw_text(canvas, badge, (canvas->width - badge_w) / 2, 60, badge_scale, fg_r, fg_g,
                       fg_b);

    host_sim_canvas_apply_round_mask(canvas);
}
