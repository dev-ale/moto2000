#include "ota_receiver.h"

#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_partition.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/sha256.h"

#include "ota_https.h"
#include "wifi_manager.h"

#include <string.h>

static const char *TAG = "ota_rx";

static struct {
    ota_rx_state_t state;
    esp_ota_handle_t handle;
    const esp_partition_t *partition;
    uint32_t total_size;
    uint32_t bytes_written;
    uint8_t expected_sha256[32];
    mbedtls_sha256_context sha_ctx;
    ota_receiver_progress_cb_t progress_cb;
} s_rx;

static inline void prv_notify(void)
{
    if (s_rx.progress_cb) {
        s_rx.progress_cb(s_rx.state, s_rx.bytes_written, s_rx.total_size);
    }
}

void ota_receiver_set_progress_cb(ota_receiver_progress_cb_t cb)
{
    s_rx.progress_cb = cb;
}

static void prv_reset(void)
{
    if (s_rx.handle != 0) {
        esp_ota_abort(s_rx.handle);
        s_rx.handle = 0;
    }
    s_rx.partition = NULL;
    s_rx.total_size = 0;
    s_rx.bytes_written = 0;
    s_rx.state = OTA_RX_IDLE;
    memset(s_rx.expected_sha256, 0, sizeof(s_rx.expected_sha256));
    mbedtls_sha256_free(&s_rx.sha_ctx);
}

void ota_receiver_init(void)
{
    memset(&s_rx, 0, sizeof(s_rx));
    mbedtls_sha256_init(&s_rx.sha_ctx);
    s_rx.state = OTA_RX_IDLE;
}

ota_rx_state_t ota_receiver_state(void)
{
    return s_rx.state;
}
uint32_t ota_receiver_bytes_written(void)
{
    return s_rx.bytes_written;
}
uint32_t ota_receiver_total_size(void)
{
    return s_rx.total_size;
}

static bool prv_handle_begin(const uint8_t *body, size_t body_len)
{
    if (body_len < 4 + 32) {
        ESP_LOGE(TAG, "BEGIN frame too short: %zu", body_len);
        return false;
    }

    /* Drop any previous session's state. */
    prv_reset();

    s_rx.total_size = (uint32_t)body[0] | ((uint32_t)body[1] << 8) | ((uint32_t)body[2] << 16) |
                      ((uint32_t)body[3] << 24);
    memcpy(s_rx.expected_sha256, body + 4, 32);

    s_rx.partition = esp_ota_get_next_update_partition(NULL);
    if (s_rx.partition == NULL) {
        ESP_LOGE(TAG, "no OTA partition available");
        s_rx.state = OTA_RX_FAILED;
        return false;
    }
    if (s_rx.total_size > s_rx.partition->size) {
        ESP_LOGE(TAG, "image %u too large for partition %u", s_rx.total_size, s_rx.partition->size);
        s_rx.state = OTA_RX_FAILED;
        return false;
    }

    esp_err_t err = esp_ota_begin(s_rx.partition, s_rx.total_size, &s_rx.handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_ota_begin failed: %s", esp_err_to_name(err));
        s_rx.state = OTA_RX_FAILED;
        return false;
    }

    mbedtls_sha256_init(&s_rx.sha_ctx);
    mbedtls_sha256_starts(&s_rx.sha_ctx, 0);

    s_rx.state = OTA_RX_RECEIVING;
    ESP_LOGI(TAG, "BEGIN: total=%u, partition=%s offset=0x%lx", s_rx.total_size,
             s_rx.partition->label, (unsigned long)s_rx.partition->address);
    prv_notify();
    return true;
}

static bool prv_handle_chunk(const uint8_t *body, size_t body_len)
{
    if (s_rx.state != OTA_RX_RECEIVING) {
        ESP_LOGW(TAG, "CHUNK in state %d", s_rx.state);
        return false;
    }
    if (body_len == 0) {
        return true;
    }
    if (s_rx.bytes_written + body_len > s_rx.total_size) {
        ESP_LOGE(TAG, "CHUNK overflow: %u+%zu > %u", s_rx.bytes_written, body_len, s_rx.total_size);
        prv_reset();
        s_rx.state = OTA_RX_FAILED;
        return false;
    }
    esp_err_t err = esp_ota_write(s_rx.handle, body, body_len);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_ota_write failed: %s", esp_err_to_name(err));
        prv_reset();
        s_rx.state = OTA_RX_FAILED;
        return false;
    }
    mbedtls_sha256_update(&s_rx.sha_ctx, body, body_len);
    s_rx.bytes_written += body_len;
    if ((s_rx.bytes_written & 0x3FFF) == 0) {
        ESP_LOGI(TAG, "CHUNK: %u/%u", s_rx.bytes_written, s_rx.total_size);
    }
    prv_notify();
    return true;
}

static bool prv_handle_commit(void)
{
    if (s_rx.state != OTA_RX_RECEIVING) {
        ESP_LOGW(TAG, "COMMIT in state %d", s_rx.state);
        return false;
    }
    if (s_rx.bytes_written != s_rx.total_size) {
        ESP_LOGE(TAG, "COMMIT short: got %u of %u", s_rx.bytes_written, s_rx.total_size);
        prv_reset();
        s_rx.state = OTA_RX_FAILED;
        return false;
    }

    s_rx.state = OTA_RX_VERIFYING;
    prv_notify();
    uint8_t actual[32];
    mbedtls_sha256_finish(&s_rx.sha_ctx, actual);
    if (memcmp(actual, s_rx.expected_sha256, 32) != 0) {
        ESP_LOGE(TAG, "SHA256 mismatch — aborting");
        prv_reset();
        s_rx.state = OTA_RX_FAILED;
        return false;
    }

    esp_err_t err = esp_ota_end(s_rx.handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_ota_end failed: %s", esp_err_to_name(err));
        s_rx.handle = 0;
        prv_reset();
        s_rx.state = OTA_RX_FAILED;
        return false;
    }
    s_rx.handle = 0;

    err = esp_ota_set_boot_partition(s_rx.partition);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "set_boot_partition failed: %s", esp_err_to_name(err));
        s_rx.state = OTA_RX_FAILED;
        return false;
    }

    s_rx.state = OTA_RX_DONE;
    prv_notify();
    ESP_LOGW(TAG, "OTA committed — rebooting in 500 ms");
    vTaskDelay(pdMS_TO_TICKS(500));
    esp_restart();
    return true; /* unreachable */
}

/* Persist the SSID half of the WiFi credentials. The password arrives
 * in a separate frame; we hold the SSID here until the password lands
 * and write both at once. Static buffers keep this state across BLE
 * write callbacks. */
static char s_pending_ssid[64];

static bool prv_handle_wifi_ssid(const uint8_t *body, size_t body_len)
{
    if (body_len == 0 || body_len >= sizeof(s_pending_ssid)) {
        return false;
    }
    memcpy(s_pending_ssid, body, body_len);
    s_pending_ssid[body_len] = '\0';
    ESP_LOGI(TAG, "wifi: stored ssid (%zu bytes)", body_len);
    return true;
}

static bool prv_handle_wifi_pwd(const uint8_t *body, size_t body_len)
{
    if (body_len >= 96)
        return false;
    char pwd[96];
    memcpy(pwd, body, body_len);
    pwd[body_len] = '\0';
    if (s_pending_ssid[0] == '\0') {
        ESP_LOGW(TAG, "wifi: password without ssid");
        return false;
    }
    esp_err_t err = wifi_manager_set_credentials(s_pending_ssid, pwd);
    /* Wipe the pending ssid so a stale value can't be reused. */
    memset(s_pending_ssid, 0, sizeof(s_pending_ssid));
    return err == ESP_OK;
}

static bool prv_handle_https_begin(const uint8_t *body, size_t body_len)
{
    if (body_len == 0 || body_len >= 240) {
        return false;
    }
    char url[256];
    memcpy(url, body, body_len);
    url[body_len] = '\0';
    ESP_LOGI(TAG, "https ota: starting (%s)", url);
    return ota_https_start(url) == ESP_OK;
}

bool ota_receiver_handle_frame(const uint8_t *data, size_t len)
{
    if (data == NULL || len < 1) {
        return false;
    }
    uint8_t type = data[0];
    const uint8_t *body = data + 1;
    size_t body_len = len - 1;

    switch (type) {
    case OTA_FRAME_WIFI_SSID:
        return prv_handle_wifi_ssid(body, body_len);
    case OTA_FRAME_WIFI_PWD:
        return prv_handle_wifi_pwd(body, body_len);
    case OTA_FRAME_HTTPS_BEGIN:
        return prv_handle_https_begin(body, body_len);
    }

    /* Legacy BLE-pushed OTA frames — unused, kept compiling. */
    switch (type) {
    case OTA_FRAME_BEGIN:
        return prv_handle_begin(body, body_len);
    case OTA_FRAME_CHUNK:
        return prv_handle_chunk(body, body_len);
    case OTA_FRAME_COMMIT:
        return prv_handle_commit();
    case OTA_FRAME_ABORT:
        ESP_LOGW(TAG, "ABORT received");
        prv_reset();
        return true;
    default:
        ESP_LOGW(TAG, "unknown frame type 0x%02x", type);
        return false;
    }
}
