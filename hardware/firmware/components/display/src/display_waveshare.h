/*
 * display_waveshare.h -- Internal header for the Waveshare ESP32-S3 1.75"
 * Round AMOLED QSPI driver.
 *
 * NOT part of the public API.  Only included by display_waveshare.c.
 *
 * References:
 *   - Waveshare ESP32-S3 1.75" AMOLED wiki:
 *     https://www.waveshare.com/wiki/ESP32-S3-LCD-1.75
 *   - Waveshare example repo (ESP-IDF):
 *     https://github.com/waveshare/Waveshare-ESP32-S3-LCD-1.75
 *   - CO5300 AMOLED controller datasheet (request from Waveshare support)
 */
#ifndef DISPLAY_WAVESHARE_H
#define DISPLAY_WAVESHARE_H

#ifdef CONFIG_IDF_TARGET_ESP32S3

#include <stdint.h>

/* ------------------------------------------------------------------ */
/* GPIO pin assignment                                                */
/* ------------------------------------------------------------------ */
/*
 * VERIFY: These pin numbers are from the Waveshare example code and wiki.
 * Verified against official Waveshare pin_config.h and ESP-IDF BSP
 * (github.com/waveshareteam/ESP32-S3-Touch-AMOLED-1.75, April 2026).
 */
#define WS_PIN_CS  12
#define WS_PIN_CLK 38
#define WS_PIN_D0  4  /* MOSI / SIO0 */
#define WS_PIN_D1  5  /* SIO1 */
#define WS_PIN_D2  6  /* SIO2 */
#define WS_PIN_D3  7  /* SIO3 */
#define WS_PIN_RST 39 /* Panel hardware reset (active low) */
#define WS_PIN_TE  -1 /* Not connected on this board revision */

/* ------------------------------------------------------------------ */
/* QSPI configuration                                                 */
/* ------------------------------------------------------------------ */

/*
 * VERIFY: Clock frequency.  The CO5300 datasheet suggests up to 50 MHz for
 * QSPI writes.  Waveshare examples use 40 MHz.  Start conservatively.
 */
#define WS_SPI_CLOCK_HZ (40 * 1000 * 1000)

/*
 * VERIFY: SPI host.  SPI2_HOST is the general-purpose SPI peripheral on
 * ESP32-S3 (SPI1 is reserved for flash).
 */
#define WS_SPI_HOST SPI2_HOST

/* Maximum transfer size in bytes.  Must accommodate the largest flush. */
#define WS_SPI_MAX_TRANSFER_SZ (466 * 48 * 2) /* ~44 KB, 1/10th screen */

/* ------------------------------------------------------------------ */
/* Panel commands                                                     */
/* ------------------------------------------------------------------ */
/*
 * VERIFY: Command set derived from CO5300-compatible init sequences found
 * in the Waveshare example code.  The exact register addresses depend on
 * the panel controller revision.
 *
 * QSPI command format (Waveshare convention):
 *   - The command byte is sent on the single SIO0 line (1-wire phase).
 *   - Parameters/data are sent on all 4 SIO lines (quad phase).
 *   - CS is managed manually or via the SPI peripheral.
 */

/* Standard MIPI DCS commands used in the init sequence. */
#define CMD_NOP          0x00
#define CMD_SW_RESET     0x01
#define CMD_SLEEP_OUT    0x11
#define CMD_DISPLAY_OFF  0x28
#define CMD_DISPLAY_ON   0x29
#define CMD_COL_ADDR_SET 0x2A /* Column address set */
#define CMD_ROW_ADDR_SET 0x2B /* Row address set */
#define CMD_MEM_WRITE    0x2C /* Memory write */
#define CMD_PIXEL_FMT    0x3A /* Pixel format set */
#define CMD_BRIGHTNESS   0x51 /* Write display brightness */
#define CMD_TEAR_ON      0x35 /* Tearing effect line ON */

/*
 * Panel initialization command table.
 *
 * Each entry: { command, num_params, param_bytes..., delay_ms }.
 * Terminated by a sentinel with cmd == 0xFF.
 *
 * VERIFY: This sequence is a best-effort reconstruction from Waveshare
 * example code.  The proprietary commands (0xFE, 0xC2, etc.) may differ
 * between board revisions.
 */
typedef struct {
    uint8_t cmd;
    uint8_t num_params;
    uint8_t params[8]; /* up to 8 params per command */
    uint16_t delay_ms;
} ws_init_cmd_t;

/*
 * CO5300 init sequence from official Waveshare ESP-IDF BSP (April 2026):
 * github.com/waveshareteam/ESP32-S3-Touch-AMOLED-1.75
 */
static const ws_init_cmd_t ws_init_cmds[] = {
    { 0xFE, 1, { 0x20 }, 0 }, /* Vendor command page 0x20 */
    { 0x19, 1, { 0x10 }, 0 },
    { 0x1C, 1, { 0xA0 }, 0 },
    { 0xFE, 1, { 0x00 }, 0 },                               /* Standard command page */
    { 0xC4, 1, { 0x80 }, 0 },                               /* Display control */
    { CMD_PIXEL_FMT, 1, { 0x55 }, 0 },                      /* RGB565 */
    { CMD_TEAR_ON, 1, { 0x00 }, 0 },                        /* Tearing effect on */
    { 0x53, 1, { 0x20 }, 0 },                               /* Brightness control */
    { CMD_BRIGHTNESS, 1, { 0xFF }, 0 },                     /* Max brightness */
    { 0x63, 1, { 0xFF }, 0 },                               /* HBM brightness max */
    { CMD_COL_ADDR_SET, 4, { 0x00, 0x06, 0x01, 0xD7 }, 0 }, /* Col 6..471 */
    { CMD_ROW_ADDR_SET, 4, { 0x00, 0x00, 0x01, 0xD1 }, 0 }, /* Row 0..465 */
    { CMD_SLEEP_OUT, 0, { 0 }, 600 },                       /* Sleep out (600ms) */
    { CMD_DISPLAY_ON, 0, { 0 }, 20 },                       /* Display ON */
    { 0xFF, 0, { 0 }, 0 },                                  /* Sentinel */
};

#endif /* CONFIG_IDF_TARGET_ESP32S3 */
#endif /* DISPLAY_WAVESHARE_H */
