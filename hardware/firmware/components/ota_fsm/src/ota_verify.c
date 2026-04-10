/*
 * ota_verify — HMAC-SHA256 implementation for OTA signature verification.
 *
 * See include/ota_verify.h for the API contract. Pure C, no ESP-IDF includes.
 * Uses the vendored sha256 implementation.
 *
 * HMAC-SHA256 as specified in RFC 2104 / FIPS 198-1:
 *   HMAC(K, m) = H((K' ^ opad) || H((K' ^ ipad) || m))
 * where K' is the key zero-padded (or hashed) to block size (64 bytes),
 * ipad = 0x36 repeated, opad = 0x5c repeated.
 */
#include "ota_verify.h"

#include "../vendor/sha256.h"

#include <string.h>

/* Constant-time comparison to prevent timing side-channels. */
static bool ct_compare(const uint8_t *a, const uint8_t *b, size_t len)
{
    uint8_t diff = 0;
    for (size_t i = 0; i < len; i++) {
        diff |= (uint8_t)(a[i] ^ b[i]);
    }
    return diff == 0;
}

static void hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *data, size_t data_len,
                        uint8_t *out_mac)
{
    uint8_t k_prime[SHA256_BLOCK_SIZE];
    uint8_t ipad[SHA256_BLOCK_SIZE];
    uint8_t opad[SHA256_BLOCK_SIZE];
    sha256_ctx_t ctx;

    memset(k_prime, 0, sizeof(k_prime));

    /* If key is longer than block size, hash it first. */
    if (key_len > SHA256_BLOCK_SIZE) {
        sha256_init(&ctx);
        sha256_update(&ctx, key, key_len);
        sha256_final(&ctx, k_prime);
    } else {
        memcpy(k_prime, key, key_len);
    }

    /* ipad = k_prime XOR 0x36, opad = k_prime XOR 0x5c */
    for (size_t i = 0; i < SHA256_BLOCK_SIZE; i++) {
        ipad[i] = (uint8_t)(k_prime[i] ^ 0x36u);
        opad[i] = (uint8_t)(k_prime[i] ^ 0x5cu);
    }

    /* Inner hash: H(ipad || message) */
    uint8_t inner_hash[SHA256_DIGEST_SIZE];
    sha256_init(&ctx);
    sha256_update(&ctx, ipad, SHA256_BLOCK_SIZE);
    if (data != NULL && data_len > 0) {
        sha256_update(&ctx, data, data_len);
    }
    sha256_final(&ctx, inner_hash);

    /* Outer hash: H(opad || inner_hash) */
    sha256_init(&ctx);
    sha256_update(&ctx, opad, SHA256_BLOCK_SIZE);
    sha256_update(&ctx, inner_hash, SHA256_DIGEST_SIZE);
    sha256_final(&ctx, out_mac);
}

bool ota_verify_hmac_sha256(const ota_verify_key_t *key, const uint8_t *data, size_t data_len,
                            const uint8_t *expected_mac, size_t mac_len)
{
    if (key == NULL || expected_mac == NULL) {
        return false;
    }
    if (mac_len != OTA_HMAC_SHA256_MAC_SIZE) {
        return false;
    }
    if (key->key_len == 0 || key->key_len > OTA_HMAC_SHA256_KEY_SIZE) {
        return false;
    }

    uint8_t computed[OTA_HMAC_SHA256_MAC_SIZE];
    hmac_sha256(key->key, key->key_len, data, data_len, computed);

    return ct_compare(computed, expected_mac, OTA_HMAC_SHA256_MAC_SIZE);
}
