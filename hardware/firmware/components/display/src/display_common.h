/*
 * display_common.h -- Internal header shared between the real driver and the
 * stub.  Not part of the public API.
 */
#ifndef DISPLAY_COMMON_H
#define DISPLAY_COMMON_H

#include "lvgl.h"
#include <stdint.h>

/*
 * Create and configure an LVGL display object with double-buffered partial
 * rendering.
 *
 * @param width      Horizontal resolution in pixels.
 * @param height     Vertical resolution in pixels.
 * @param flush_cb   LVGL flush callback (platform-specific).
 * @param user_data  Opaque pointer passed to the flush callback.
 *
 * Returns the lv_display_t* on success, NULL on allocation failure.
 */
lv_display_t *display_create_lvgl(uint32_t width, uint32_t height,
                                   lv_display_flush_cb_t flush_cb,
                                   void *user_data);

#endif /* DISPLAY_COMMON_H */
