/*
 * trip_stats_layout.c — pure-C helpers for the Trip Stats screen.
 *
 * Same constraints as speed_layout.c: zero canvas / SDL / PNG deps so
 * Unity host tests can drive every formatter without spinning the
 * rasteriser.
 */
#include "host_sim/trip_stats_layout.h"

#include <stdio.h>
#include <string.h>

size_t host_sim_format_distance(uint32_t meters, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len < 12U) {
        return 0U;
    }
    int n;
    if (meters < 1000U) {
        n = snprintf(buf, buf_len, "%u M", (unsigned int)meters);
    } else if (meters < 100000U) {
        /* one-decimal km — round half-up at the 0.1 km level (= 100 m) */
        const unsigned int hundreds = (meters + 50U) / 100U; /* 0.1 km units */
        const unsigned int whole    = hundreds / 10U;
        const unsigned int frac     = hundreds % 10U;
        n = snprintf(buf, buf_len, "%u.%u KM", whole, frac);
    } else {
        const unsigned int km = (meters + 500U) / 1000U;
        n = snprintf(buf, buf_len, "%u KM", km);
    }
    if (n < 0 || (size_t)n >= buf_len) {
        return 0U;
    }
    return (size_t)n;
}

size_t host_sim_format_duration(uint32_t seconds, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len < 12U) {
        return 0U;
    }
    unsigned int hours   = (unsigned int)(seconds / 3600U);
    unsigned int minutes = (unsigned int)((seconds % 3600U) / 60U);
    unsigned int secs    = (unsigned int)(seconds % 60U);
    if (hours > 99U) {
        hours   = 99U;
        minutes = 59U;
        secs    = 59U;
    }
    int n;
    if (hours == 0U) {
        n = snprintf(buf, buf_len, "%02u:%02u", minutes, secs);
    } else {
        n = snprintf(buf, buf_len, "%u:%02u:%02u", hours, minutes, secs);
    }
    if (n < 0 || (size_t)n >= buf_len) {
        return 0U;
    }
    return (size_t)n;
}

size_t host_sim_format_speed_cell(const char *prefix,
                                  uint16_t    speed_kmh_x10,
                                  char       *buf,
                                  size_t      buf_len)
{
    if (buf == NULL || prefix == NULL || buf_len < 16U) {
        return 0U;
    }
    unsigned int kmh = ((unsigned int)speed_kmh_x10 + 5U) / 10U;
    if (kmh > 999U) {
        kmh = 999U;
    }
    const int n = snprintf(buf, buf_len, "%s %u KM/H", prefix, kmh);
    if (n < 0 || (size_t)n >= buf_len) {
        return 0U;
    }
    return (size_t)n;
}

size_t host_sim_format_elevation_delta(uint16_t meters,
                                       int      is_descent,
                                       char    *buf,
                                       size_t   buf_len)
{
    if (buf == NULL || buf_len < 8U) {
        return 0U;
    }
    const char sign = is_descent ? '-' : '+';
    const int  n    = snprintf(buf, buf_len, "%c%uM", sign, (unsigned int)meters);
    if (n < 0 || (size_t)n >= buf_len) {
        return 0U;
    }
    return (size_t)n;
}
