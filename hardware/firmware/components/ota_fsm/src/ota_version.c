/*
 * ota_version — implementation.
 *
 * See include/ota_version.h for the API contract. Pure C, no ESP-IDF includes.
 */
#include "ota_version.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int ota_version_compare(const ota_version_t *a, const ota_version_t *b)
{
    if (a == NULL || b == NULL) {
        return 0;
    }
    if (a->major != b->major) {
        return (a->major > b->major) ? 1 : -1;
    }
    if (a->minor != b->minor) {
        return (a->minor > b->minor) ? 1 : -1;
    }
    if (a->patch != b->patch) {
        return (a->patch > b->patch) ? 1 : -1;
    }
    return 0;
}

bool ota_version_is_newer(const ota_version_t *current, const ota_version_t *available)
{
    if (current == NULL || available == NULL) {
        return false;
    }
    return ota_version_compare(available, current) > 0;
}

void ota_version_to_string(const ota_version_t *v, char *buf, size_t buf_len)
{
    if (v == NULL || buf == NULL || buf_len == 0) {
        return;
    }
    (void)snprintf(buf, buf_len, "%u.%u.%u", (unsigned)v->major, (unsigned)v->minor,
                   (unsigned)v->patch);
}

bool ota_version_parse(const char *str, ota_version_t *out)
{
    if (str == NULL || out == NULL) {
        return false;
    }

    /* Manual parsing to avoid locale-dependent strtol and to validate
     * that there is no trailing garbage. */
    const char *p = str;
    unsigned long parts[3];

    for (int i = 0; i < 3; i++) {
        if (*p == '\0') {
            return false;
        }
        /* Must start with a digit. */
        if (*p < '0' || *p > '9') {
            return false;
        }
        char *end = NULL;
        unsigned long val = strtoul(p, &end, 10);
        if (end == p) {
            return false;
        }
        if (val > 255u) {
            return false;
        }
        parts[i] = val;
        p = end;
        if (i < 2) {
            if (*p != '.') {
                return false;
            }
            p++; /* skip the dot */
        }
    }

    /* Reject trailing characters. */
    if (*p != '\0') {
        return false;
    }

    out->major = (uint8_t)parts[0];
    out->minor = (uint8_t)parts[1];
    out->patch = (uint8_t)parts[2];
    return true;
}
