/*
 * main.c — ScramScreen LVGL simulator entry point.
 *
 * This is the ONLY file with SDL-specific code. All screen files use
 * pure LVGL APIs so they can compile on the ESP32 unchanged.
 *
 * Modes:
 *   One-shot: ./scramscreen-lvgl-sim --in payload.bin
 *             Renders one frame in an SDL window and waits for the user
 *             to close it (or press Q/ESC).
 *
 *   Live:     ./scramscreen-lvgl-sim --live
 *             Opens an SDL window, reads hex-encoded payloads from stdin
 *             (one per line), re-renders on each.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>

#include "lvgl.h"
#include "common/screen_manager.h"
#include "theme/scram_theme.h"

#include <sys/select.h>

#include <SDL2/SDL.h>

#define DISPLAY_W   466
#define DISPLAY_H   466
#define MAX_PAYLOAD 4096U

/* ------------------------------------------------------------------ */
/*  Helpers                                                           */
/* ------------------------------------------------------------------ */

static int read_file(const char *path, uint8_t *buf, size_t cap, size_t *out_len)
{
    FILE *f = fopen(path, "rb");
    if (!f) return 1;
    size_t total = 0;
    while (total < cap) {
        size_t got = fread(buf + total, 1, cap - total, f);
        if (got == 0) break;
        total += got;
    }
    fclose(f);
    *out_len = total;
    return total > 0 ? 0 : 1;
}

static int hex_to_bytes(const char *hex, uint8_t *out, size_t cap, size_t *out_len)
{
    size_t slen = strlen(hex);
    /* Strip trailing newline. */
    while (slen > 0 && (hex[slen - 1] == '\n' || hex[slen - 1] == '\r')) {
        slen--;
    }
    if (slen % 2 != 0) return 1;
    size_t n = slen / 2;
    if (n > cap) return 1;
    for (size_t i = 0; i < n; i++) {
        unsigned int byte;
        if (sscanf(hex + i * 2, "%2x", &byte) != 1) return 1;
        out[i] = (uint8_t)byte;
    }
    *out_len = n;
    return 0;
}

static void usage(void)
{
    fputs(
        "Usage:\n"
        "  scramscreen-lvgl-sim --in <payload.bin>   Render one frame\n"
        "  scramscreen-lvgl-sim --live                Live mode (hex on stdin)\n"
        "\n"
        "Options:\n"
        "  --in <file>   Read a raw BLE payload from file\n"
        "  --live        Accept hex-encoded payloads on stdin, one per line\n"
        "  -h, --help    Show this help\n",
        stderr);
}

/* ------------------------------------------------------------------ */
/*  LVGL tick                                                         */
/* ------------------------------------------------------------------ */

static uint32_t sdl_tick_get(void)
{
    return SDL_GetTicks();
}

/* ------------------------------------------------------------------ */
/*  SDL flush callback for LVGL display driver                        */
/* ------------------------------------------------------------------ */

typedef struct {
    SDL_Window   *window;
    SDL_Renderer *renderer;
    SDL_Texture  *texture;
} sdl_ctx_t;

static sdl_ctx_t s_sdl;

static void sdl_flush_cb(lv_display_t *disp, const lv_area_t *area,
                          uint8_t *px_map)
{
    /* Update the texture region with the rendered pixels. */
    int w = lv_area_get_width(area);
    int h = lv_area_get_height(area);

    SDL_Rect rect = {
        .x = area->x1,
        .y = area->y1,
        .w = w,
        .h = h,
    };
    SDL_UpdateTexture(s_sdl.texture, &rect, px_map, w * 4);

    if (lv_display_flush_is_last(disp)) {
        SDL_RenderClear(s_sdl.renderer);
        SDL_RenderCopy(s_sdl.renderer, s_sdl.texture, NULL, NULL);
        SDL_RenderPresent(s_sdl.renderer);
    }

    lv_display_flush_ready(disp);
}

/* ------------------------------------------------------------------ */
/*  Main                                                              */
/* ------------------------------------------------------------------ */

int main(int argc, char **argv)
{
    const char *in_path = NULL;
    bool live_mode = false;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--in") == 0 && i + 1 < argc) {
            in_path = argv[++i];
        } else if (strcmp(argv[i], "--live") == 0) {
            live_mode = true;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage();
            return 0;
        } else {
            fprintf(stderr, "Unknown argument: %s\n", argv[i]);
            usage();
            return 1;
        }
    }
    if (!in_path && !live_mode) {
        fprintf(stderr, "Error: specify --in <file> or --live\n");
        usage();
        return 1;
    }

    /* --- SDL init --- */
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    s_sdl.window = SDL_CreateWindow(
        "ScramScreen LVGL Simulator",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        DISPLAY_W, DISPLAY_H,
        SDL_WINDOW_SHOWN | SDL_WINDOW_ALLOW_HIGHDPI);
    if (!s_sdl.window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    s_sdl.renderer = SDL_CreateRenderer(s_sdl.window, -1,
                                        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!s_sdl.renderer) {
        s_sdl.renderer = SDL_CreateRenderer(s_sdl.window, -1, SDL_RENDERER_SOFTWARE);
    }
    if (!s_sdl.renderer) {
        fprintf(stderr, "SDL_CreateRenderer failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(s_sdl.window);
        SDL_Quit();
        return 1;
    }

    s_sdl.texture = SDL_CreateTexture(s_sdl.renderer,
                                      SDL_PIXELFORMAT_ARGB8888,
                                      SDL_TEXTUREACCESS_STREAMING,
                                      DISPLAY_W, DISPLAY_H);
    if (!s_sdl.texture) {
        fprintf(stderr, "SDL_CreateTexture failed: %s\n", SDL_GetError());
        SDL_DestroyRenderer(s_sdl.renderer);
        SDL_DestroyWindow(s_sdl.window);
        SDL_Quit();
        return 1;
    }

    /* --- LVGL init --- */
    lv_init();
    lv_tick_set_cb(sdl_tick_get);

    /* Create display with manual flush. */
    lv_display_t *disp = lv_display_create(DISPLAY_W, DISPLAY_H);

    /* Allocate draw buffers. */
    static uint8_t buf1[DISPLAY_W * DISPLAY_H / 10 * 4];
    lv_display_set_buffers(disp, buf1, NULL, sizeof(buf1),
                           LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(disp, sdl_flush_cb);
    lv_display_set_color_format(disp, LV_COLOR_FORMAT_ARGB8888);

    /* Apply ScramScreen theme. */
    scram_theme_apply(disp);

    /* Init screen manager. */
    screen_manager_init();

    /* --- Load initial payload (one-shot mode) --- */
    if (in_path) {
        uint8_t payload[MAX_PAYLOAD];
        size_t  payload_len = 0;
        if (read_file(in_path, payload, sizeof(payload), &payload_len) != 0) {
            fprintf(stderr, "Failed to read %s\n", in_path);
            SDL_DestroyTexture(s_sdl.texture);
            SDL_DestroyRenderer(s_sdl.renderer);
            SDL_DestroyWindow(s_sdl.window);
            SDL_Quit();
            return 1;
        }
        screen_manager_handle_payload(payload, payload_len);
    }

    /* --- Event loop --- */
    bool running = true;
    while (running) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) {
                running = false;
            }
            if (ev.type == SDL_KEYDOWN) {
                if (ev.key.keysym.sym == SDLK_q ||
                    ev.key.keysym.sym == SDLK_ESCAPE) {
                    running = false;
                }
            }
        }

        /* In live mode, check stdin for a new hex payload (non-blocking). */
        if (live_mode) {
            fd_set fds;
            struct timeval tv = {0, 0};
            FD_ZERO(&fds);
            FD_SET(0, &fds);
            if (select(1, &fds, NULL, NULL, &tv) > 0) {
                char line[MAX_PAYLOAD * 2 + 2];
                if (fgets(line, (int)sizeof(line), stdin) != NULL) {
                    uint8_t payload[MAX_PAYLOAD];
                    size_t  payload_len = 0;
                    if (hex_to_bytes(line, payload, sizeof(payload), &payload_len) == 0) {
                        screen_manager_handle_payload(payload, payload_len);
                    } else {
                        fprintf(stderr, "Invalid hex line, ignoring\n");
                    }
                } else {
                    /* EOF on stdin — exit live mode. */
                    running = false;
                }
            }
        }

        lv_timer_handler();
        SDL_Delay(5);
    }

    /* --- Cleanup --- */
    SDL_DestroyTexture(s_sdl.texture);
    SDL_DestroyRenderer(s_sdl.renderer);
    SDL_DestroyWindow(s_sdl.window);
    SDL_Quit();
    return 0;
}
