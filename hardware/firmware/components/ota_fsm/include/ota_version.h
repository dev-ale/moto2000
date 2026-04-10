/*
 * ota_version — firmware version comparison for OTA updates.
 *
 * Pure C, no ESP-IDF dependencies. Provides semantic-version comparison
 * (major.minor.patch) and string conversion helpers.
 */
#ifndef SCRAMSCREEN_OTA_VERSION_H
#define SCRAMSCREEN_OTA_VERSION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t patch;
} ota_version_t;

/*
 * Returns true if `available` is strictly newer than `current`.
 */
bool ota_version_is_newer(const ota_version_t *current, const ota_version_t *available);

/*
 * Three-way comparison: returns <0 if a < b, 0 if a == b, >0 if a > b.
 */
int ota_version_compare(const ota_version_t *a, const ota_version_t *b);

/*
 * Writes "major.minor.patch" into buf. buf_len must be >= 12 to hold the
 * longest possible string "255.255.255\0". If buf_len is 0, nothing is
 * written.
 */
void ota_version_to_string(const ota_version_t *v, char *buf, size_t buf_len);

/*
 * Parses "major.minor.patch" from a null-terminated string. Returns true on
 * success, false if the format is invalid. Each component must be 0..255.
 */
bool ota_version_parse(const char *str, ota_version_t *out);

#ifdef __cplusplus
}
#endif

#endif /* SCRAMSCREEN_OTA_VERSION_H */
