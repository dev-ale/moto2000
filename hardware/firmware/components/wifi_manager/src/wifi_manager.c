#include "wifi_manager.h"

#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "nvs.h"
#include "nvs_flash.h"

#include <string.h>

static const char *TAG = "wifi_mgr";
static const char *NVS_NS = "scram_wifi";
static const char *NVS_KEY_SSID = "ssid";
static const char *NVS_KEY_PWD = "pwd";

#define WIFI_CONNECTED_BIT BIT0
#define WIFI_FAIL_BIT      BIT1

static EventGroupHandle_t s_event_group;
static bool s_initialised;
static esp_netif_t *s_sta_netif;
static int s_retry_count;

static void prv_event_handler(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    (void)arg;
    (void)data;
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        if (s_retry_count < 5) {
            s_retry_count++;
            ESP_LOGW(TAG, "disconnected, retry %d", s_retry_count);
            esp_wifi_connect();
        } else {
            xEventGroupSetBits(s_event_group, WIFI_FAIL_BIT);
        }
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ESP_LOGI(TAG, "got IP");
        s_retry_count = 0;
        xEventGroupSetBits(s_event_group, WIFI_CONNECTED_BIT);
    }
}

esp_err_t wifi_manager_init(void)
{
    if (s_initialised)
        return ESP_OK;

    /* NVS is already initialised by app_main, but guard anyway. */
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        err = nvs_flash_init();
    }
    if (err != ESP_OK)
        return err;

    s_event_group = xEventGroupCreate();
    if (!s_event_group)
        return ESP_ERR_NO_MEM;

    /* netif + event loop are created by the BSP and main respectively;
     * we create them here only if missing. */
    if (esp_netif_init() != ESP_OK) {
        ESP_LOGW(TAG, "esp_netif_init returned non-ok (likely already done)");
    }
    esp_event_loop_create_default(); /* idempotent failure ok */

    s_sta_netif = esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    err = esp_wifi_init(&cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_wifi_init: %s", esp_err_to_name(err));
        return err;
    }

    esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &prv_event_handler, NULL,
                                        NULL);
    esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &prv_event_handler, NULL,
                                        NULL);

    err = esp_wifi_set_mode(WIFI_MODE_STA);
    if (err != ESP_OK)
        return err;

    /* Don't start yet — keep the radio off until the OTA flow asks. */
    s_initialised = true;
    return ESP_OK;
}

esp_err_t wifi_manager_set_credentials(const char *ssid, const char *password)
{
    if (!ssid || !password)
        return ESP_ERR_INVALID_ARG;
    nvs_handle_t h;
    esp_err_t err = nvs_open(NVS_NS, NVS_READWRITE, &h);
    if (err != ESP_OK)
        return err;
    nvs_set_str(h, NVS_KEY_SSID, ssid);
    nvs_set_str(h, NVS_KEY_PWD, password);
    err = nvs_commit(h);
    nvs_close(h);
    ESP_LOGI(TAG, "stored credentials: ssid='%s' pwd_len=%zu", ssid, strlen(password));
    return err;
}

bool wifi_manager_get_credentials(char *ssid_out, size_t ssid_cap, char *pwd_out, size_t pwd_cap)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READONLY, &h) != ESP_OK)
        return false;
    size_t ssid_len = ssid_cap, pwd_len = pwd_cap;
    esp_err_t e1 = nvs_get_str(h, NVS_KEY_SSID, ssid_out, &ssid_len);
    esp_err_t e2 = nvs_get_str(h, NVS_KEY_PWD, pwd_out, &pwd_len);
    nvs_close(h);
    return e1 == ESP_OK && e2 == ESP_OK && strlen(ssid_out) > 0;
}

esp_err_t wifi_manager_connect_blocking(uint32_t timeout_ms)
{
    if (!s_initialised) {
        esp_err_t err = wifi_manager_init();
        if (err != ESP_OK)
            return err;
    }

    char ssid[WIFI_MAX_SSID_LEN + 1] = { 0 };
    char password[WIFI_MAX_PWD_LEN + 1] = { 0 };
    if (!wifi_manager_get_credentials(ssid, sizeof(ssid), password, sizeof(password))) {
        ESP_LOGE(TAG, "no stored credentials");
        return ESP_ERR_NOT_FOUND;
    }

    wifi_config_t wifi_cfg = { 0 };
    strncpy((char *)wifi_cfg.sta.ssid, ssid, sizeof(wifi_cfg.sta.ssid) - 1);
    strncpy((char *)wifi_cfg.sta.password, password, sizeof(wifi_cfg.sta.password) - 1);
    wifi_cfg.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;

    esp_wifi_set_config(WIFI_IF_STA, &wifi_cfg);

    s_retry_count = 0;
    xEventGroupClearBits(s_event_group, WIFI_CONNECTED_BIT | WIFI_FAIL_BIT);
    esp_err_t err = esp_wifi_start();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_wifi_start: %s", esp_err_to_name(err));
        return err;
    }

    EventBits_t bits = xEventGroupWaitBits(s_event_group, WIFI_CONNECTED_BIT | WIFI_FAIL_BIT,
                                           pdFALSE, pdFALSE, timeout_ms / portTICK_PERIOD_MS);

    if (bits & WIFI_CONNECTED_BIT) {
        return ESP_OK;
    }
    ESP_LOGE(TAG, "connect failed (bits=0x%x)", (unsigned)bits);
    esp_wifi_stop();
    return ESP_FAIL;
}

void wifi_manager_disconnect(void)
{
    esp_wifi_disconnect();
    esp_wifi_stop();
}
