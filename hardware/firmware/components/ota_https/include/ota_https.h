/*
 * ota_https — wraps esp_https_ota with a progress callback so the UI
 * can render a percentage as the binary streams in.
 *
 * Call ota_https_run() from a dedicated task. It connects WiFi,
 * fetches the URL, applies the image, and reboots on success.
 */
#ifndef OTA_HTTPS_H
#define OTA_HTTPS_H

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    OTA_HTTPS_IDLE = 0,
    OTA_HTTPS_CONNECTING_WIFI,
    OTA_HTTPS_DOWNLOADING,
    OTA_HTTPS_VERIFYING,
    OTA_HTTPS_DONE,
    OTA_HTTPS_FAILED,
} ota_https_state_t;

typedef void (*ota_https_progress_cb_t)(ota_https_state_t state, int bytes_read, int total_bytes,
                                        const char *message);

void ota_https_set_progress_cb(ota_https_progress_cb_t cb);

/* Kick off the OTA. Spawns a dedicated FreeRTOS task; returns immediately.
 * The task connects WiFi, downloads from `url`, applies and reboots. */
esp_err_t ota_https_start(const char *url);

#ifdef __cplusplus
}
#endif

#endif /* OTA_HTTPS_H */
