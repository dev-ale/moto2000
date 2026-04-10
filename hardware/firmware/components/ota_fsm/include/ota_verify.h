/*
 * ota_verify — HMAC-SHA256 signature verification for OTA firmware images.
 *
 * Pure C, no ESP-IDF dependencies. Uses the vendored SHA256 implementation
 * under vendor/sha256.{c,h}.
 *
 * For the MVP we use HMAC-SHA256 rather than Ed25519 because it is simpler
 * to implement with a single-file dependency and sufficient for a device
 * that communicates over a trusted local channel. A future slice may upgrade
 * to Ed25519 (asymmetric) signing.
 */
#ifndef SCRAMSCREEN_OTA_VERIFY_H
#define SCRAMSCREEN_OTA_VERIFY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define OTA_HMAC_SHA256_KEY_SIZE  32
#define OTA_HMAC_SHA256_MAC_SIZE  32

typedef struct {
    uint8_t key[OTA_HMAC_SHA256_KEY_SIZE];
    size_t  key_len; /* 1..32 */
} ota_verify_key_t;

/*
 * Compute HMAC-SHA256 over `data` using `key` and compare with
 * `expected_mac`. Returns true iff the MAC matches. mac_len must be
 * exactly OTA_HMAC_SHA256_MAC_SIZE (32) or the function returns false.
 *
 * NULL data with data_len==0 is valid (HMAC of empty message).
 * NULL key or NULL expected_mac returns false.
 */
bool ota_verify_hmac_sha256(const ota_verify_key_t *key,
                            const uint8_t *data, size_t data_len,
                            const uint8_t *expected_mac, size_t mac_len);

#ifdef __cplusplus
}
#endif

#endif /* SCRAMSCREEN_OTA_VERIFY_H */
