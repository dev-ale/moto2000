/*
 * renderer.h — host simulator rendering surface.
 *
 * The host simulator renders ScramScreen screens into a fixed-size RGB888
 * buffer shaped to the real AMOLED panel (466×466, round). The buffer is
 * then serialised as a PNG for snapshot tests.
 *
 * NOTE on graphics backend: the issue tracker refers to this as the "LVGL
 * host simulator". In practice, Slice 1.5b ships a pure-C software
 * rasteriser that is deterministic, offline, and trivially reproducible on
 * CI — no LVGL v9 FetchContent, no SDL, no dynamic linking. Every screen
 * lives behind a `host_sim_render_*` function that only touches the RGB
 * buffer, so a follow-up slice can swap the backend for real LVGL without
 * touching the rest of the simulator (main.c, PNG writer, snapshot
 * harness, Swift transport). See host-sim/README.md for the rationale.
 */
#ifndef HOST_SIM_RENDERER_H
#define HOST_SIM_RENDERER_H

#include <stddef.h>
#include <stdint.h>

#include "ble_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

#define HOST_SIM_DISPLAY_WIDTH  466
#define HOST_SIM_DISPLAY_HEIGHT 466

/* RGB888 framebuffer, row-major, no padding. */
typedef struct {
    uint8_t *pixels; /* HOST_SIM_DISPLAY_WIDTH*HOST_SIM_DISPLAY_HEIGHT*3 bytes */
    int width;
    int height;
} host_sim_canvas_t;

/* Allocate a fresh canvas. Caller owns and must free with host_sim_canvas_destroy(). */
host_sim_canvas_t *host_sim_canvas_create(void);
void host_sim_canvas_destroy(host_sim_canvas_t *canvas);

/* Fill the canvas with a single RGB colour. */
void host_sim_canvas_fill(host_sim_canvas_t *canvas, uint8_t r, uint8_t g, uint8_t b);

/* Draw a filled round display background (mask everything outside the circle
 * to the off-panel colour). Call this *after* drawing screen contents. */
void host_sim_canvas_apply_round_mask(host_sim_canvas_t *canvas);

/* Screen-specific renderers. They each take the already-decoded payload
 * and draw into `canvas`. The canvas is expected to be pre-filled with
 * the background colour the screen wants. */
void host_sim_render_clock(host_sim_canvas_t *canvas, const ble_clock_data_t *clock, uint8_t flags);

void host_sim_render_compass(host_sim_canvas_t *canvas, const ble_compass_data_t *compass,
                             uint8_t header_flags);

void host_sim_render_speed(host_sim_canvas_t *canvas, const ble_speed_heading_data_t *data,
                           uint8_t flags);

void host_sim_render_navigation(host_sim_canvas_t *canvas, const ble_nav_data_t *nav,
                                uint8_t flags);

void host_sim_render_trip_stats(host_sim_canvas_t *canvas, const ble_trip_stats_data_t *data,
                                uint8_t flags);

void host_sim_render_weather(host_sim_canvas_t *canvas, const ble_weather_data_t *weather,
                             uint8_t flags);

void host_sim_render_lean_angle(host_sim_canvas_t *canvas, const ble_lean_angle_data_t *lean,
                                uint8_t header_flags);

void host_sim_render_music(host_sim_canvas_t *canvas, const ble_music_data_t *music,
                           uint8_t header_flags);

void host_sim_render_appointment(host_sim_canvas_t *canvas,
                                 const ble_appointment_data_t *appointment, uint8_t header_flags);

void host_sim_render_fuel(host_sim_canvas_t *canvas, const ble_fuel_data_t *fuel,
                          uint8_t header_flags);

void host_sim_render_altitude(host_sim_canvas_t *canvas, const ble_altitude_profile_data_t *alt,
                              uint8_t header_flags);

void host_sim_render_call(host_sim_canvas_t *canvas, const ble_incoming_call_data_t *call,
                          uint8_t header_flags);

void host_sim_render_blitzer(host_sim_canvas_t *canvas, const ble_blitzer_data_t *blitzer,
                             uint8_t header_flags);

/* Placeholder for screens that have not been implemented yet. Draws a
 * "screen 0xNN pending" message on a dark background. */
void host_sim_render_placeholder(host_sim_canvas_t *canvas, uint8_t screen_id);

/* Dispatch on screen id. Returns 0 on success, non-zero on decode error
 * (caller should check stderr). On decode failure a red error screen is
 * still rendered so snapshot diffs fail loudly instead of silently. */
int host_sim_render_payload(host_sim_canvas_t *canvas, const uint8_t *payload, size_t length);

/* Serialise the canvas as a PNG to the given path. Returns 0 on success. */
int host_sim_canvas_write_png(const host_sim_canvas_t *canvas, const char *path);

#ifdef __cplusplus
}
#endif

#endif /* HOST_SIM_RENDERER_H */
