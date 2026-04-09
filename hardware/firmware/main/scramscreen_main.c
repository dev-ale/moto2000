/*
 * ScramScreen — custom round AMOLED motorcycle display
 *
 * This is the firmware entry point. Real feature work begins in Slice 2
 * (issue #3). For now this is a smoke-test stub that logs boot info so
 * `idf.py build && idf.py flash monitor` proves the toolchain works.
 */

#include "esp_log.h"
#include "esp_system.h"
#include "nvs_flash.h"

static const char *TAG = "scramscreen";

void app_main(void)
{
    ESP_LOGI(TAG, "ScramScreen booting — firmware stub");

    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    ESP_LOGI(TAG, "NVS initialized — ready for feature work in Slice 2");
}
