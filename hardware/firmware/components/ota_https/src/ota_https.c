#include "ota_https.h"

#include "esp_crt_bundle.h"
#include "esp_http_client.h"
#include "esp_https_ota.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "wifi_manager.h"

#include <string.h>

static const char *TAG = "ota_https";

static ota_https_progress_cb_t s_progress_cb;
static char s_url[256];
static TaskHandle_t s_task;

void ota_https_set_progress_cb(ota_https_progress_cb_t cb)
{
    s_progress_cb = cb;
}

static void prv_emit(ota_https_state_t state, int read, int total, const char *msg)
{
    ESP_LOGI(TAG, "state=%d read=%d total=%d msg=%s", state, read, total, msg ? msg : "");
    if (s_progress_cb) {
        s_progress_cb(state, read, total, msg);
    }
}

static void prv_ota_task(void *arg)
{
    (void)arg;

    /* 1. Connect WiFi */
    prv_emit(OTA_HTTPS_CONNECTING_WIFI, 0, 0, "Connecting to WiFi");
    esp_err_t err = wifi_manager_connect_blocking(20000);
    if (err != ESP_OK) {
        prv_emit(OTA_HTTPS_FAILED, 0, 0, "WiFi connect failed");
        s_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    /* 2. esp_https_ota begin/perform/finish loop with progress */
    esp_http_client_config_t http_config = {
        .url = s_url,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 30000,
        .keep_alive_enable = true,
    };
    esp_https_ota_config_t ota_config = {
        .http_config = &http_config,
    };

    esp_https_ota_handle_t handle = NULL;
    err = esp_https_ota_begin(&ota_config, &handle);
    if (err != ESP_OK) {
        prv_emit(OTA_HTTPS_FAILED, 0, 0, esp_err_to_name(err));
        wifi_manager_disconnect();
        s_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    int total = esp_https_ota_get_image_size(handle);
    prv_emit(OTA_HTTPS_DOWNLOADING, 0, total, "Downloading");

    int last_emit = -1;
    while (true) {
        err = esp_https_ota_perform(handle);
        if (err != ESP_ERR_HTTPS_OTA_IN_PROGRESS)
            break;
        int read = esp_https_ota_get_image_len_read(handle);
        int pct = (total > 0) ? (read * 100 / total) : 0;
        if (pct != last_emit) {
            last_emit = pct;
            prv_emit(OTA_HTTPS_DOWNLOADING, read, total, NULL);
        }
    }

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "perform failed: %s", esp_err_to_name(err));
        esp_https_ota_abort(handle);
        prv_emit(OTA_HTTPS_FAILED, 0, total, esp_err_to_name(err));
        wifi_manager_disconnect();
        s_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    prv_emit(OTA_HTTPS_VERIFYING, total, total, "Verifying");
    err = esp_https_ota_finish(handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "finish failed: %s", esp_err_to_name(err));
        prv_emit(OTA_HTTPS_FAILED, total, total, esp_err_to_name(err));
        wifi_manager_disconnect();
        s_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    prv_emit(OTA_HTTPS_DONE, total, total, "Restarting");
    wifi_manager_disconnect();
    vTaskDelay(pdMS_TO_TICKS(800));
    esp_restart();
}

esp_err_t ota_https_start(const char *url)
{
    if (!url)
        return ESP_ERR_INVALID_ARG;
    if (s_task)
        return ESP_ERR_INVALID_STATE;
    strncpy(s_url, url, sizeof(s_url) - 1);
    s_url[sizeof(s_url) - 1] = '\0';
    BaseType_t rc = xTaskCreate(prv_ota_task, "ota_https", 8192, NULL, 5, &s_task);
    return (rc == pdPASS) ? ESP_OK : ESP_FAIL;
}
