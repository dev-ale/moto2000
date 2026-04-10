/*
 * display_common.c -- Shared LVGL display creation logic.
 *
 * Used by both display_waveshare.c (ESP-IDF) and display_stub.c (host).
 * Allocates double buffers and registers the flush callback with LVGL.
 */

#include "display_common.h"
#include "display.h"

#include <stdlib.h>

/* ------------------------------------------------------------------ */
/* Platform-specific allocation                                       */
/* ------------------------------------------------------------------ */

#ifdef CONFIG_IDF_TARGET_ESP32S3
#include "esp_heap_caps.h"

static void *platform_alloc(size_t size)
{
    /*
     * Prefer DMA-capable internal SRAM for the flush buffer so the SPI
     * peripheral can read it directly.  Fall back to PSRAM if internal
     * memory is exhausted (the buffer is ~43 KB at 1/10th screen).
     */
    void *p = heap_caps_malloc(size, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    if (!p) {
        p = heap_caps_malloc(size, MALLOC_CAP_SPIRAM);
    }
    return p;
}

#else /* Host / non-ESP build */

static void *platform_alloc(size_t size)
{
    return malloc(size);
}

#endif

/* ------------------------------------------------------------------ */
/* LVGL display creation                                              */
/* ------------------------------------------------------------------ */

/*
 * Buffer size: 1/10th of the full framebuffer.  With RGB565 (2 bytes/pixel)
 * and 466x466 resolution that is ~43 KB per buffer.  Two buffers enable
 * double-buffered partial rendering.
 */
#define BUF_LINES  (DISPLAY_HEIGHT / 10)

lv_display_t *display_create_lvgl(uint32_t width, uint32_t height,
                                   lv_display_flush_cb_t flush_cb,
                                   void *user_data)
{
    lv_display_t *disp = lv_display_create((int32_t)width, (int32_t)height);
    if (!disp) {
        return NULL;
    }

    /*
     * Allocate two partial-screen buffers.  Using sizeof(lv_color_t) adapts
     * to the configured LV_COLOR_DEPTH (32-bit on the simulator, 16-bit
     * RGB565 on the target).
     */
    size_t buf_size = (size_t)width * BUF_LINES * sizeof(lv_color_t);

    uint8_t *buf1 = (uint8_t *)platform_alloc(buf_size);
    uint8_t *buf2 = (uint8_t *)platform_alloc(buf_size);

    if (!buf1 || !buf2) {
        /* If one succeeded and the other didn't, free the successful one. */
        free(buf1);
        free(buf2);
        /* LVGL v9.2 does not expose lv_display_delete(); leave orphan. */
        return NULL;
    }

    lv_display_set_buffers(disp, buf1, buf2, buf_size,
                           LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(disp, flush_cb);
    lv_display_set_user_data(disp, user_data);

    return disp;
}
