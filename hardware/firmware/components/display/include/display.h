/*
 * display.h -- ScramScreen display driver public API.
 *
 * Two implementations exist behind this interface:
 *   - display_waveshare.c  (ESP-IDF, QSPI AMOLED on Waveshare ESP32-S3 board)
 *   - display_stub.c       (host builds, no-op stub for integration testing)
 *
 * Both share display_common.c for the LVGL display-object setup.
 */
#ifndef DISPLAY_H
#define DISPLAY_H

#include <stdint.h>
#include <stdbool.h>

/* Waveshare ESP32-S3 1.75" Round AMOLED -- 466x466 pixels. */
#define DISPLAY_WIDTH   466
#define DISPLAY_HEIGHT  466

/*
 * Initialize the display hardware and create the LVGL display driver.
 *
 * On ESP32-S3: configures QSPI bus, sends panel init commands, creates LVGL
 *              display with DMA-capable double buffers in internal SRAM.
 * On host:     creates a stub LVGL display (flush callback is a no-op).
 *
 * Returns 0 on success, negative errno-style code on failure.
 */
int display_init(void);

/*
 * Set panel brightness.
 *
 * @param percent  Brightness 0..100 (0 = off, 100 = full brightness).
 *
 * On ESP32-S3: sends brightness command over QSPI to the AMOLED controller.
 * On host:     no-op, always returns 0.
 *
 * Returns 0 on success, negative errno-style code on failure.
 */
int display_set_brightness(uint8_t percent);

/*
 * Retrieve the LVGL display object created during display_init().
 *
 * Returns the lv_display_t* (cast to void* to avoid requiring lvgl.h in every
 * translation unit that includes this header).  Returns NULL before init.
 */
void *display_get_lv_display(void);

#endif /* DISPLAY_H */
