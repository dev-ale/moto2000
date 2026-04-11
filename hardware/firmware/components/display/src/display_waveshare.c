/*
 * display_waveshare.c -- QSPI AMOLED driver for the Waveshare ESP32-S3 1.75"
 * Round AMOLED Display.
 *
 * This file is compiled ONLY under ESP-IDF for the ESP32-S3 target.  On host
 * builds the stub (display_stub.c) provides the display.h implementation.
 *
 * Hardware:
 *   - Panel: 466x466 round AMOLED, CO5300 (or compatible) controller
 *   - Interface: QSPI (4-wire SPI with quad data lines)
 *   - Color: RGB565 (16 bpp) for bandwidth efficiency
 *
 * References:
 *   - Waveshare wiki: https://www.waveshare.com/wiki/ESP32-S3-LCD-1.75
 *   - Waveshare example: https://github.com/waveshare/Waveshare-ESP32-S3-LCD-1.75
 *   - ESP-IDF SPI Master:
 * https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32s3/api-reference/peripherals/spi_master.html
 *
 * VERIFY: This entire file is written from documentation and example code
 * without access to the physical board.  Every hardware-specific constant
 * and command sequence should be verified on the real hardware.
 */

#ifdef CONFIG_IDF_TARGET_ESP32S3

#include "display.h"
#include "display_common.h"
#include "display_waveshare.h"

#include "lvgl.h"

#include "driver/spi_master.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include <string.h>

static const char *TAG = "display_ws";

/* ------------------------------------------------------------------ */
/* Module state                                                       */
/* ------------------------------------------------------------------ */

static spi_device_handle_t s_spi_dev;
static lv_display_t *s_display;

/* ------------------------------------------------------------------ */
/* Low-level QSPI helpers                                             */
/* ------------------------------------------------------------------ */

/*
 * Send a single command byte (1-wire) with optional parameter bytes (quad).
 *
 * VERIFY: The Waveshare QSPI protocol sends the command in the "address"
 * phase (single-line) and data in the "data" phase (quad).  The command
 * byte is shifted into bits [31:24] of the address field with addr_bits=8.
 * Some implementations use a 32-bit address with the command in the high
 * byte -- check the Waveshare example for the exact framing.
 */
static esp_err_t ws_send_cmd(uint8_t cmd, const uint8_t *params, size_t len)
{
    spi_transaction_t txn;
    memset(&txn, 0, sizeof(txn));

    /*
     * VERIFY: Command framing.
     *
     * Waveshare convention for CO5300 over QSPI:
     *   - The "command" phase uses the SPI address field (single line).
     *   - cmd byte is placed in bits [31:24], with 0x02 write indicator
     *     in bits [23:16] and dummy bits below.
     *   - Parameter bytes go in the data phase (quad lines).
     *
     * This framing may differ.  The Waveshare example code is the
     * authoritative reference.
     */
    txn.flags = SPI_TRANS_MULTILINE_ADDR;
    txn.cmd = 0x02;                  /* VERIFY: write command prefix */
    txn.addr = ((uint32_t)cmd) << 8; /* VERIFY: address framing */

    if (params && len > 0) {
        txn.tx_buffer = params;
        txn.length = len * 8; /* bits */
    }

    return spi_device_transmit(s_spi_dev, &txn);
}

/*
 * Send pixel data for a previously set window.
 *
 * Uses the Memory Write command (0x2C) with the pixel buffer in quad mode.
 */
static esp_err_t ws_send_pixels(const uint8_t *data, size_t len)
{
    spi_transaction_t txn;
    memset(&txn, 0, sizeof(txn));

    /*
     * VERIFY: For large transfers the SPI master driver requires the buffer
     * to be DMA-capable (allocated with MALLOC_CAP_DMA).  The LVGL buffers
     * allocated in display_common.c satisfy this requirement.
     */
    txn.flags = SPI_TRANS_MULTILINE_ADDR;
    txn.cmd = 0x32; /* VERIFY: quad write prefix */
    txn.addr = ((uint32_t)CMD_MEM_WRITE) << 8;

    txn.tx_buffer = data;
    txn.length = len * 8; /* bits */

    return spi_device_transmit(s_spi_dev, &txn);
}

/* ------------------------------------------------------------------ */
/* Panel init / reset                                                 */
/* ------------------------------------------------------------------ */

static void ws_hardware_reset(void)
{
    gpio_set_level((gpio_num_t)WS_PIN_RST, 0);
    vTaskDelay(pdMS_TO_TICKS(20));
    gpio_set_level((gpio_num_t)WS_PIN_RST, 1);
    vTaskDelay(pdMS_TO_TICKS(120));
}

static esp_err_t ws_panel_init(void)
{
    ws_hardware_reset();

    for (int i = 0; ws_init_cmds[i].cmd != 0xFF; i++) {
        const ws_init_cmd_t *c = &ws_init_cmds[i];
        esp_err_t err = ws_send_cmd(c->cmd, c->params, c->num_params);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "Init cmd 0x%02X failed: %s", c->cmd, esp_err_to_name(err));
            return err;
        }
        if (c->delay_ms > 0) {
            vTaskDelay(pdMS_TO_TICKS(c->delay_ms));
        }
    }

    ESP_LOGI(TAG, "Panel init complete");
    return ESP_OK;
}

/* ------------------------------------------------------------------ */
/* Set display window (column/row address)                            */
/* ------------------------------------------------------------------ */

/*
 * Column offset = 6, verified from official Waveshare BSP:
 * esp_lcd_panel_set_gap(panel_handle, 0x06, 0)
 */
#define COL_OFFSET 6
#define ROW_OFFSET 0

static esp_err_t ws_set_window(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1)
{
    uint8_t col_params[4] = {
        (uint8_t)((x0 + COL_OFFSET) >> 8),
        (uint8_t)(x0 + COL_OFFSET),
        (uint8_t)((x1 + COL_OFFSET) >> 8),
        (uint8_t)(x1 + COL_OFFSET),
    };
    uint8_t row_params[4] = {
        (uint8_t)((y0 + ROW_OFFSET) >> 8),
        (uint8_t)(y0 + ROW_OFFSET),
        (uint8_t)((y1 + ROW_OFFSET) >> 8),
        (uint8_t)(y1 + ROW_OFFSET),
    };

    esp_err_t err = ws_send_cmd(CMD_COL_ADDR_SET, col_params, sizeof(col_params));
    if (err != ESP_OK)
        return err;

    return ws_send_cmd(CMD_ROW_ADDR_SET, row_params, sizeof(row_params));
}

/* ------------------------------------------------------------------ */
/* LVGL flush callback                                                */
/* ------------------------------------------------------------------ */

static void display_flush_cb(lv_display_t *disp, const lv_area_t *area, uint8_t *px_map)
{
    uint16_t x0 = (uint16_t)area->x1;
    uint16_t y0 = (uint16_t)area->y1;
    uint16_t x1 = (uint16_t)area->x2;
    uint16_t y1 = (uint16_t)area->y2;

    ws_set_window(x0, y0, x1, y1);

    size_t len = (size_t)(x1 - x0 + 1) * (size_t)(y1 - y0 + 1) * 2; /* RGB565 = 2 bytes/pixel */
    ws_send_pixels(px_map, len);

    lv_display_flush_ready(disp);
}

/* ------------------------------------------------------------------ */
/* SPI bus + device initialization                                    */
/* ------------------------------------------------------------------ */

static esp_err_t ws_spi_init(void)
{
    esp_err_t err;

    /* Configure RST pin as output. */
    gpio_config_t rst_cfg = {
        .pin_bit_mask = (1ULL << WS_PIN_RST),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&rst_cfg);
    gpio_set_level((gpio_num_t)WS_PIN_RST, 1);

    /*
     * VERIFY: TE (tearing effect) pin configuration.  For now we configure
     * it as input but do not attach an interrupt.  A future optimization
     * can synchronize flushes to the TE signal to avoid tearing.
     */
    gpio_config_t te_cfg = {
        .pin_bit_mask = (1ULL << WS_PIN_TE),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&te_cfg);

    /*
     * SPI bus configuration for QSPI (quad mode).
     *
     * VERIFY: The data_io_num fields.  In quad mode the SPI master driver
     * uses data0..data3 for the four data lines.  The mosi_io_num is set
     * to -1 because data is sent via the quadio pins.
     */
    spi_bus_config_t bus_cfg = {
        .mosi_io_num = -1,
        .miso_io_num = -1,
        .sclk_io_num = WS_PIN_CLK,
        .data0_io_num = WS_PIN_D0,
        .data1_io_num = WS_PIN_D1,
        .data2_io_num = WS_PIN_D2,
        .data3_io_num = WS_PIN_D3,
        .max_transfer_sz = WS_SPI_MAX_TRANSFER_SZ,
        .flags = SPICOMMON_BUSFLAG_QUAD,
    };

    err = spi_bus_initialize(WS_SPI_HOST, &bus_cfg, SPI_DMA_CH_AUTO);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "SPI bus init failed: %s", esp_err_to_name(err));
        return err;
    }

    /*
     * SPI device configuration.
     *
     * VERIFY: command_bits and address_bits framing.  The CO5300 QSPI
     * protocol sends an 8-bit command prefix on a single line, then an
     * address (containing the actual DCS command), then data on quad lines.
     * The exact bit counts depend on the Waveshare protocol wrapper.
     */
    spi_device_interface_config_t dev_cfg = {
        .command_bits = 8,
        .address_bits = 24,
        .mode = 0, /* VERIFY: SPI mode 0 (CPOL=0 CPHA=0) */
        .clock_speed_hz = WS_SPI_CLOCK_HZ,
        .spics_io_num = WS_PIN_CS,
        .queue_size = 7,
        .flags = SPI_DEVICE_HALFDUPLEX,
    };

    err = spi_bus_add_device(WS_SPI_HOST, &dev_cfg, &s_spi_dev);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "SPI add device failed: %s", esp_err_to_name(err));
        return err;
    }

    ESP_LOGI(TAG, "SPI bus initialized (QSPI, %d MHz)", WS_SPI_CLOCK_HZ / 1000000);
    return ESP_OK;
}

/* ------------------------------------------------------------------ */
/* Public API                                                         */
/* ------------------------------------------------------------------ */

int display_init(void)
{
    if (s_display) {
        return 0; /* already initialized */
    }

    esp_err_t err = ws_spi_init();
    if (err != ESP_OK) {
        return -1;
    }

    err = ws_panel_init();
    if (err != ESP_OK) {
        return -1;
    }

    s_display = display_create_lvgl(DISPLAY_WIDTH, DISPLAY_HEIGHT, display_flush_cb, NULL);
    if (!s_display) {
        ESP_LOGE(TAG, "LVGL display creation failed");
        return -1;
    }

    ESP_LOGI(TAG, "Display initialized (%dx%d)", DISPLAY_WIDTH, DISPLAY_HEIGHT);
    return 0;
}

int display_set_brightness(uint8_t percent)
{
    if (percent > 100) {
        percent = 100;
    }

    /*
     * Map 0..100% to 0..255 for the AMOLED brightness register.
     * VERIFY: The CO5300 CMD_BRIGHTNESS (0x51) accepts 0x00..0xFF.
     */
    uint8_t value = (uint8_t)((uint16_t)percent * 255 / 100);
    esp_err_t err = ws_send_cmd(CMD_BRIGHTNESS, &value, 1);

    return (err == ESP_OK) ? 0 : -1;
}

void *display_get_lv_display(void)
{
    return s_display;
}

#endif /* CONFIG_IDF_TARGET_ESP32S3 */
