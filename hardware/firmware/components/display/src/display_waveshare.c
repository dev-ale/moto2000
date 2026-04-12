/*
 * display_waveshare.c -- Uses official Waveshare BSP for display init.
 */

#include "sdkconfig.h"
#ifdef CONFIG_IDF_TARGET_ESP32S3

#include "display.h"
#include "display_common.h"
#include "lvgl.h"
#include "bsp/esp-bsp.h"
#include "bsp/display.h"
#include "esp_log.h"

static const char *TAG = "display_ws";
static lv_display_t *s_display = NULL;

int display_init(void)
{
    /* Use the official Waveshare BSP — it handles everything:
     * SPI bus, CO5300 panel, QSPI framing, LVGL adapter, brightness.
     */
    s_display = bsp_display_start();
    if (!s_display) {
        ESP_LOGE(TAG, "bsp_display_start failed");
        return -1;
    }

    bsp_display_brightness_set(80);

    ESP_LOGI(TAG, "Display initialized via Waveshare BSP (%dx%d)", BSP_LCD_H_RES, BSP_LCD_V_RES);
    return 0;
}

int display_set_brightness(uint8_t percent)
{
    return bsp_display_brightness_set(percent) == ESP_OK ? 0 : -1;
}

void *display_get_lv_display(void)
{
    return s_display;
}

#endif /* CONFIG_IDF_TARGET_ESP32S3 */
