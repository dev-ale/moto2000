/*
 * appointment_layout.c — pure helpers for the appointment screen.
 */
#include "host_sim/appointment_layout.h"

#include <stdio.h>
#include <string.h>

void host_sim_appointment_format_starts_in(int16_t minutes, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0U) {
        return;
    }
    if (minutes == 0) {
        (void)snprintf(buf, buf_len, "NOW");
    } else if (minutes > 0) {
        (void)snprintf(buf, buf_len, "IN %dM", (int)minutes);
    } else {
        (void)snprintf(buf, buf_len, "%dM AGO", (int)(-minutes));
    }
}

static void uppercase_truncate(const char *in, char *out, size_t out_len, size_t max_chars)
{
    if (out == NULL || out_len == 0U) {
        return;
    }
    if (in == NULL) {
        out[0] = '\0';
        return;
    }
    size_t i = 0U;
    while (in[i] != '\0' && i < max_chars && (i + 1U) < out_len) {
        const char c = in[i];
        if (c >= 'a' && c <= 'z') {
            out[i] = (char)(c - 'a' + 'A');
        } else {
            out[i] = c;
        }
        ++i;
    }
    out[i] = '\0';
}

void host_sim_appointment_uppercase_title(const char *in, char *out, size_t out_len)
{
    uppercase_truncate(in, out, out_len, APPOINTMENT_LAYOUT_MAX_TITLE_CHARS);
}

void host_sim_appointment_uppercase_location(const char *in, char *out, size_t out_len)
{
    uppercase_truncate(in, out, out_len, APPOINTMENT_LAYOUT_MAX_LOCATION_CHARS);
}
