/*
 * screen_trip_stats.c — renders the Trip Stats screen onto the round
 * 466x466 panel.
 *
 * Layout:
 *   - Background: deep navy (#0A1C3A) day, black night.
 *   - Hero distance ("7.4 KM" / "127 KM" / "950 M") top-centre, large.
 *   - Ride time below ("00:24" or "1:24:17"), medium.
 *   - Bottom half:
 *       - "AVG <n> KM/H" left, "MAX <n> KM/H" right
 *       - "+<asc>M"     left, "-<dsc>M"      right
 *   - Night mode mirrors compass/clock: black bg, red-shifted glyphs.
 */
#include "host_sim/renderer.h"
#include "host_sim/trip_stats_layout.h"
#include "text_draw.h"

#include <string.h>

#include "ble_protocol.h"

void host_sim_render_trip_stats(host_sim_canvas_t *canvas, const ble_trip_stats_data_t *data,
                                uint8_t flags)
{
    const bool night = (flags & BLE_FLAG_NIGHT_MODE) != 0U;
    if (night) {
        host_sim_canvas_fill(canvas, 0, 0, 0);
    } else {
        host_sim_canvas_fill(canvas, 0x0A, 0x1C, 0x3A);
    }

    const uint8_t fg_r = 0xFFU;
    const uint8_t fg_g = night ? 0x33U : 0xFFU;
    const uint8_t fg_b = night ? 0x33U : 0xFFU;
    const uint8_t muted_r = night ? 0xAAU : 0x88U;
    const uint8_t muted_g = night ? 0x22U : 0x99U;
    const uint8_t muted_b = night ? 0x22U : 0xAAU;
    const uint8_t accent_r = night ? 0xFFU : 0x66U;
    const uint8_t accent_g = night ? 0x55U : 0xCCU;
    const uint8_t accent_b = night ? 0x55U : 0xFFU;

    /* ---------------- hero distance ---------------- */
    char dist_buf[16];
    (void)host_sim_format_distance(data->distance_meters, dist_buf, sizeof(dist_buf));
    const int dist_scale = 7;
    const int dist_w = host_sim_measure_text(dist_buf, dist_scale);
    const int dist_x = (canvas->width - dist_w) / 2;
    const int dist_y = 110;
    host_sim_draw_text(canvas, dist_buf, dist_x, dist_y, dist_scale, fg_r, fg_g, fg_b);

    /* ---------------- ride time ---------------- */
    char dur_buf[16];
    (void)host_sim_format_duration(data->ride_time_seconds, dur_buf, sizeof(dur_buf));
    const int dur_scale = 4;
    const int dur_w = host_sim_measure_text(dur_buf, dur_scale);
    const int dur_x = (canvas->width - dur_w) / 2;
    const int dur_y = dist_y + 8 * dist_scale + 18;
    host_sim_draw_text(canvas, dur_buf, dur_x, dur_y, dur_scale, accent_r, accent_g, accent_b);

    /* ---------------- avg / max speed cells ---------------- */
    char avg_buf[16];
    char max_buf[16];
    (void)host_sim_format_speed_cell("AVG", data->average_speed_kmh_x10, avg_buf, sizeof(avg_buf));
    (void)host_sim_format_speed_cell("MAX", data->max_speed_kmh_x10, max_buf, sizeof(max_buf));
    const int speed_scale = 2;
    const int speed_y = dur_y + 8 * dur_scale + 32;
    const int half_w = canvas->width / 2;
    const int avg_w = host_sim_measure_text(avg_buf, speed_scale);
    const int max_w = host_sim_measure_text(max_buf, speed_scale);
    const int avg_x = (half_w - avg_w) / 2;
    const int max_x = half_w + (half_w - max_w) / 2;
    host_sim_draw_text(canvas, avg_buf, avg_x, speed_y, speed_scale, muted_r, muted_g, muted_b);
    host_sim_draw_text(canvas, max_buf, max_x, speed_y, speed_scale, muted_r, muted_g, muted_b);

    /* ---------------- ascent / descent cells ---------------- */
    char asc_buf[12];
    char dsc_buf[12];
    (void)host_sim_format_elevation_delta(data->ascent_meters, 0, asc_buf, sizeof(asc_buf));
    (void)host_sim_format_elevation_delta(data->descent_meters, 1, dsc_buf, sizeof(dsc_buf));
    const int elev_scale = 2;
    const int elev_y = speed_y + 8 * speed_scale + 22;
    const int asc_w = host_sim_measure_text(asc_buf, elev_scale);
    const int dsc_w = host_sim_measure_text(dsc_buf, elev_scale);
    const int asc_x = (half_w - asc_w) / 2;
    const int dsc_x = half_w + (half_w - dsc_w) / 2;
    host_sim_draw_text(canvas, asc_buf, asc_x, elev_y, elev_scale, muted_r, muted_g, muted_b);
    host_sim_draw_text(canvas, dsc_buf, dsc_x, elev_y, elev_scale, muted_r, muted_g, muted_b);

    host_sim_canvas_apply_round_mask(canvas);
}
