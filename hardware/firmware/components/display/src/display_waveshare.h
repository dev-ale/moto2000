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
 * Cross-check with your actual board revision's schematic.
 */
#define WS_PIN_CS     6
#define WS_PIN_CLK    47
#define WS_PIN_D0     18   /* MOSI / SIO0 */
#define WS_PIN_D1     7    /* SIO1 */
#define WS_PIN_D2     48   /* SIO2 */
#define WS_PIN_D3     5    /* SIO3 */
#define WS_PIN_RST    17   /* Panel hardware reset (active low) */
#define WS_PIN_TE     9    /* Tearing-effect output from panel (vsync) */

/* ------------------------------------------------------------------ */
/* QSPI configuration                                                 */
/* ------------------------------------------------------------------ */

/*
 * VERIFY: Clock frequency.  The CO5300 datasheet suggests up to 50 MHz for
 * QSPI writes.  Waveshare examples use 40 MHz.  Start conservatively.
 */
#define WS_SPI_CLOCK_HZ  (40 * 1000 * 1000)

/*
 * VERIFY: SPI host.  SPI2_HOST is the general-purpose SPI peripheral on
 * ESP32-S3 (SPI1 is reserved for flash).
 */
#define WS_SPI_HOST       SPI2_HOST

/* Maximum transfer size in bytes.  Must accommodate the largest flush. */
#define WS_SPI_MAX_TRANSFER_SZ  (466 * 48 * 2)  /* ~44 KB, 1/10th screen */

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
#define CMD_NOP           0x00
#define CMD_SW_RESET      0x01
#define CMD_SLEEP_OUT     0x11
#define CMD_DISPLAY_OFF   0x28
#define CMD_DISPLAY_ON    0x29
#define CMD_COL_ADDR_SET  0x2A  /* Column address set */
#define CMD_ROW_ADDR_SET  0x2B  /* Row address set */
#define CMD_MEM_WRITE     0x2C  /* Memory write */
#define CMD_PIXEL_FMT     0x3A  /* Pixel format set */
#define CMD_BRIGHTNESS    0x51  /* Write display brightness */
#define CMD_TEAR_ON       0x35  /* Tearing effect line ON */

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
    uint8_t params[8];     /* up to 8 params per command */
    uint16_t delay_ms;
} ws_init_cmd_t;

/*
 * VERIFY: Every entry in this table.  Sourced from Waveshare example code
 * and CO5300 datasheet references.  Proprietary vendor commands may change
 * between hardware revisions.
 */
static const ws_init_cmd_t ws_init_cmds[] = {
    /* Enable command page (vendor-specific). */
    /* VERIFY: 0xFE is the command-page-select register on CO5300. */
    { 0xFE, 1, { 0x00 }, 0 },

    /* Software reset. */
    { CMD_SW_RESET, 0, { 0 }, 120 },

    /* Sleep out — panel needs ~120 ms to wake. */
    { CMD_SLEEP_OUT, 0, { 0 }, 120 },

    /*
     * Pixel format: 0x55 = 16-bit/pixel RGB565 for both RGB and MCU
     * interface.  RGB565 is chosen for bandwidth efficiency over QSPI.
     * VERIFY: Waveshare example uses RGB565 (0x55).  For RGB888 use 0x77.
     */
    { CMD_PIXEL_FMT, 1, { 0x55 }, 0 },

    /* Enable tearing effect output on TE pin (mode 0 = v-blank only). */
    { CMD_TEAR_ON, 1, { 0x00 }, 0 },

    /* Set initial brightness to 100%. */
    { CMD_BRIGHTNESS, 1, { 0xFF }, 0 },

    /* Display ON. */
    { CMD_DISPLAY_ON, 0, { 0 }, 20 },

    /* Sentinel — end of table. */
    { 0xFF, 0, { 0 }, 0 },
};

#endif /* CONFIG_IDF_TARGET_ESP32S3 */
#endif /* DISPLAY_WAVESHARE_H */
