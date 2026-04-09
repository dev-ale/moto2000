/*
 * music_layout.c — deterministic helpers for the music screen renderer.
 */
#include "host_sim/music_layout.h"

#include <stdio.h>
#include <string.h>

int host_sim_music_progress_fill_width(uint16_t position_seconds,
                                       uint16_t duration_seconds,
                                       int      bar_width)
{
    if (bar_width < 0) {
        return 0;
    }
    if (position_seconds == HOST_SIM_MUSIC_UNKNOWN_U16 ||
        duration_seconds == HOST_SIM_MUSIC_UNKNOWN_U16) {
        return -1;
    }
    if (duration_seconds == 0U) {
        return 0;
    }
    if (position_seconds >= duration_seconds) {
        return bar_width;
    }
    const uint32_t numerator = (uint32_t)position_seconds * (uint32_t)bar_width;
    const uint32_t fill      = numerator / (uint32_t)duration_seconds;
    return (int)fill;
}

size_t host_sim_music_truncate_with_ellipsis(const char *in,
                                             char       *out,
                                             size_t      out_len)
{
    if (out == NULL || out_len == 0U) {
        return 0;
    }
    if (in == NULL) {
        out[0] = '\0';
        return 0;
    }
    const size_t in_len = strlen(in);
    if (in_len + 1U <= out_len) {
        memcpy(out, in, in_len);
        out[in_len] = '\0';
        return in_len;
    }
    /* Need room for "..\0". If out_len < 3 we can only write as much as
     * fits plus NUL. */
    if (out_len < 4U) {
        size_t fit = out_len - 1U;
        if (fit > 2U) {
            fit = 2U;
        }
        for (size_t i = 0; i < fit; ++i) {
            out[i] = '.';
        }
        out[fit] = '\0';
        return fit;
    }
    const size_t keep = out_len - 3U;  /* leave room for "..\0" */
    memcpy(out, in, keep);
    out[keep]     = '.';
    out[keep + 1] = '.';
    out[keep + 2] = '\0';
    return keep + 2U;
}

void host_sim_music_uppercase_ascii(const char *in,
                                    char       *out,
                                    size_t      out_len)
{
    if (out == NULL || out_len == 0U) {
        return;
    }
    if (in == NULL) {
        out[0] = '\0';
        return;
    }
    size_t i = 0;
    for (; i + 1U < out_len && in[i] != '\0'; ++i) {
        char c = in[i];
        if (c >= 'a' && c <= 'z') {
            c = (char)(c - ('a' - 'A'));
        }
        out[i] = c;
    }
    out[i] = '\0';
}

size_t host_sim_music_format_time(uint16_t seconds,
                                  char    *buf,
                                  size_t   buf_len)
{
    if (buf == NULL || buf_len < 6U) {
        return 0;
    }
    if (seconds == HOST_SIM_MUSIC_UNKNOWN_U16) {
        const char *sentinel = "--:--";
        const size_t len = strlen(sentinel);
        memcpy(buf, sentinel, len + 1U);
        return len;
    }
    const unsigned minutes = (unsigned)(seconds / 60U);
    const unsigned secs    = (unsigned)(seconds % 60U);
    int written;
    if (minutes >= 10U) {
        written = snprintf(buf, buf_len, "%u:%02u", minutes, secs);
    } else {
        written = snprintf(buf, buf_len, "%u:%02u", minutes, secs);
    }
    if (written < 0 || (size_t)written >= buf_len) {
        buf[0] = '\0';
        return 0;
    }
    return (size_t)written;
}
