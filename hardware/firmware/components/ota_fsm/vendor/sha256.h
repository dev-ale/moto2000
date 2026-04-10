/*
 * sha256.h — SHA-256 hash function.
 *
 * Based on Brad Conte's crypto-algorithms (public domain).
 * https://github.com/B-Con/crypto-algorithms
 *
 * Vendored into ScramScreen for OTA signature verification so we have no
 * external FetchContent dependency for crypto.
 */
#ifndef SCRAMSCREEN_VENDOR_SHA256_H
#define SCRAMSCREEN_VENDOR_SHA256_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SHA256_BLOCK_SIZE  64
#define SHA256_DIGEST_SIZE 32

typedef struct {
    uint8_t  data[64];
    uint32_t datalen;
    uint64_t bitlen;
    uint32_t state[8];
} sha256_ctx_t;

void sha256_init(sha256_ctx_t *ctx);
void sha256_update(sha256_ctx_t *ctx, const uint8_t *data, size_t len);
void sha256_final(sha256_ctx_t *ctx, uint8_t *hash);

#ifdef __cplusplus
}
#endif

#endif /* SCRAMSCREEN_VENDOR_SHA256_H */
