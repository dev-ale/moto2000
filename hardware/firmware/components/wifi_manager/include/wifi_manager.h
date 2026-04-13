/*
 * wifi_manager — minimal STA-only WiFi front end for the OTA flow.
 *
 * Credentials live in NVS under "scram_wifi/ssid" + "scram_wifi/pwd".
 * Once stored they survive reboots. The OTA flow calls
 * wifi_manager_connect_blocking() right before kicking off
 * esp_https_ota and disconnects after the fetch completes.
 */
#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define WIFI_MAX_SSID_LEN 32
#define WIFI_MAX_PWD_LEN  64

/* Initialise NVS namespace + WiFi stack (STA mode, not yet connected). */
esp_err_t wifi_manager_init(void);

/* Persist new credentials. Either field may be empty. */
esp_err_t wifi_manager_set_credentials(const char *ssid, const char *password);

/* Read stored credentials into the provided buffers. Returns true if both
 * fields are non-empty. */
bool wifi_manager_get_credentials(char *ssid_out, size_t ssid_cap, char *pwd_out, size_t pwd_cap);

/* Connect to the stored WiFi network and block up to `timeout_ms` ms
 * waiting for an IP. Returns ESP_OK on success. */
esp_err_t wifi_manager_connect_blocking(uint32_t timeout_ms);

/* Disconnect and stop the WiFi stack. */
void wifi_manager_disconnect(void);

#ifdef __cplusplus
}
#endif

#endif /* WIFI_MANAGER_H */
