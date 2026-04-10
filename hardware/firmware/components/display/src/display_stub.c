/*
 * display_stub.c -- No-op display driver for host builds.
 *
 * Implements the display.h public API with a dummy LVGL display so that
 * higher-level firmware code can be compiled and tested on the host without
 * any ESP-IDF or real hardware dependencies.
 *
 * The stub flush callback immediately signals completion to LVGL without
 * sending any pixel data.
 */

#include "display.h"
#include "display_common.h"

#include "lvgl.h"

static lv_display_t *s_display;

/* ------------------------------------------------------------------ */
/* Stub flush callback                                                */
/* ------------------------------------------------------------------ */

static void stub_flush_cb(lv_display_t *disp,
                           const lv_area_t *area,
                           uint8_t *px_map)
{
    (void)area;
    (void)px_map;
    lv_display_flush_ready(disp);
}

/* ------------------------------------------------------------------ */
/* Public API                                                         */
/* ------------------------------------------------------------------ */

int display_init(void)
{
    if (s_display) {
        return 0; /* already initialized */
    }

    s_display = display_create_lvgl(DISPLAY_WIDTH, DISPLAY_HEIGHT,
                                     stub_flush_cb, NULL);
    return s_display ? 0 : -1;
}

int display_set_brightness(uint8_t percent)
{
    (void)percent;
    return 0;
}

void *display_get_lv_display(void)
{
    return s_display;
}
