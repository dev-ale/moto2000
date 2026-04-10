/*
 * renderer.c — canvas allocation, primitives, and dispatch.
 */
#include "host_sim/renderer.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ble_protocol.h"

host_sim_canvas_t *host_sim_canvas_create(void)
{
    host_sim_canvas_t *c = calloc(1, sizeof(*c));
    if (c == NULL) {
        return NULL;
    }
    c->width  = HOST_SIM_DISPLAY_WIDTH;
    c->height = HOST_SIM_DISPLAY_HEIGHT;
    const size_t bytes =
        (size_t)c->width * (size_t)c->height * 3U;
    c->pixels = calloc(bytes, 1U);
    if (c->pixels == NULL) {
        free(c);
        return NULL;
    }
    return c;
}

void host_sim_canvas_destroy(host_sim_canvas_t *canvas)
{
    if (canvas == NULL) {
        return;
    }
    free(canvas->pixels);
    free(canvas);
}

void host_sim_canvas_fill(host_sim_canvas_t *canvas, uint8_t r, uint8_t g, uint8_t b)
{
    if (canvas == NULL || canvas->pixels == NULL) {
        return;
    }
    const size_t pixel_count = (size_t)canvas->width * (size_t)canvas->height;
    for (size_t i = 0; i < pixel_count; ++i) {
        canvas->pixels[i * 3U + 0U] = r;
        canvas->pixels[i * 3U + 1U] = g;
        canvas->pixels[i * 3U + 2U] = b;
    }
}

void host_sim_canvas_apply_round_mask(host_sim_canvas_t *canvas)
{
    if (canvas == NULL || canvas->pixels == NULL) {
        return;
    }
    const int cx = canvas->width / 2;
    const int cy = canvas->height / 2;
    const int r  = canvas->width / 2;
    const int r2 = r * r;
    for (int y = 0; y < canvas->height; ++y) {
        for (int x = 0; x < canvas->width; ++x) {
            const int dx = x - cx;
            const int dy = y - cy;
            if (dx * dx + dy * dy > r2) {
                const size_t idx = ((size_t)y * (size_t)canvas->width + (size_t)x) * 3U;
                canvas->pixels[idx + 0U] = 0;
                canvas->pixels[idx + 1U] = 0;
                canvas->pixels[idx + 2U] = 0;
            }
        }
    }
}

int host_sim_render_payload(host_sim_canvas_t *canvas,
                            const uint8_t     *payload,
                            size_t             length)
{
    if (canvas == NULL || payload == NULL || length == 0U) {
        return 1;
    }
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(payload, length, &header);
    if (hdr != BLE_OK) {
        fprintf(stderr,
                "host-sim: failed to decode header: %s\n",
                ble_result_name(hdr));
        host_sim_canvas_fill(canvas, 200, 0, 0);
        host_sim_canvas_apply_round_mask(canvas);
        return 2;
    }
    switch (header.screen_id) {
        case BLE_SCREEN_COMPASS: {
            ble_compass_data_t compass;
            uint8_t            flags = 0;
            const ble_result_t res =
                ble_decode_compass(payload, length, &flags, &compass);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode compass body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_compass(canvas, &compass, flags);
            return 0;
        }
        case BLE_SCREEN_CLOCK: {
            ble_clock_data_t clock;
            uint8_t          flags = 0;
            const ble_result_t res =
                ble_decode_clock(payload, length, &flags, &clock);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode clock body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_clock(canvas, &clock, flags);
            return 0;
        }
        case BLE_SCREEN_SPEED_HEADING: {
            ble_speed_heading_data_t speed;
            uint8_t            flags = 0;
            const ble_result_t res =
                ble_decode_speed_heading(payload, length, &flags, &speed);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode speed+heading body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_speed(canvas, &speed, flags);
            return 0;
        }
        case BLE_SCREEN_TRIP_STATS: {
            ble_trip_stats_data_t stats;
            uint8_t            flags = 0;
            const ble_result_t res =
                ble_decode_trip_stats(payload, length, &flags, &stats);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode trip stats body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_trip_stats(canvas, &stats, flags);
            return 0;
        }
        case BLE_SCREEN_WEATHER: {
            ble_weather_data_t weather;
            uint8_t            flags = 0;
            const ble_result_t res =
                ble_decode_weather(payload, length, &flags, &weather);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode weather body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_weather(canvas, &weather, flags);
            return 0;
        }
        case BLE_SCREEN_LEAN_ANGLE: {
            ble_lean_angle_data_t lean;
            uint8_t               flags = 0;
            const ble_result_t    res =
                ble_decode_lean_angle(payload, length, &flags, &lean);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode lean angle body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_lean_angle(canvas, &lean, flags);
            return 0;
        }
        case BLE_SCREEN_MUSIC: {
            ble_music_data_t music;
            uint8_t          flags = 0;
            const ble_result_t res =
                ble_decode_music(payload, length, &flags, &music);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode music body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_music(canvas, &music, flags);
            return 0;
        }
        case BLE_SCREEN_APPOINTMENT: {
            ble_appointment_data_t appointment;
            uint8_t                flags = 0;
            const ble_result_t res =
                ble_decode_appointment(payload, length, &flags, &appointment);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode appointment body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_appointment(canvas, &appointment, flags);
            return 0;
        }
        case BLE_SCREEN_NAVIGATION: {
            ble_nav_data_t nav;
            uint8_t        flags = 0;
            const ble_result_t res =
                ble_decode_nav(payload, length, &flags, &nav);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode nav body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_navigation(canvas, &nav, flags);
            return 0;
        }
        case BLE_SCREEN_FUEL_ESTIMATE: {
            ble_fuel_data_t fuel;
            uint8_t         flags = 0;
            const ble_result_t res =
                ble_decode_fuel(payload, length, &flags, &fuel);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode fuel body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_fuel(canvas, &fuel, flags);
            return 0;
        }
        case BLE_SCREEN_ALTITUDE: {
            ble_altitude_profile_data_t alt;
            uint8_t         flags = 0;
            const ble_result_t res =
                ble_decode_altitude(payload, length, &flags, &alt);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode altitude body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_altitude(canvas, &alt, flags);
            return 0;
        }
        case BLE_SCREEN_INCOMING_CALL: {
            ble_incoming_call_data_t call;
            uint8_t         flags = 0;
            const ble_result_t res =
                ble_decode_incoming_call(payload, length, &flags, &call);
            if (res != BLE_OK) {
                fprintf(stderr,
                        "host-sim: failed to decode incoming call body: %s\n",
                        ble_result_name(res));
                host_sim_canvas_fill(canvas, 200, 0, 0);
                host_sim_canvas_apply_round_mask(canvas);
                return 3;
            }
            host_sim_render_call(canvas, &call, flags);
            return 0;
        }
        default:
            host_sim_render_placeholder(canvas, (uint8_t)header.screen_id);
            return 0;
    }
}
