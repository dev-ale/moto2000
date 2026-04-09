/*
 * time_format.h — pure C time formatting for the clock screen.
 *
 * Split out from the renderer so it can be unit-tested on the host with
 * Unity without pulling the whole rasteriser into the test binary.
 */
#ifndef HOST_SIM_TIME_FORMAT_H
#define HOST_SIM_TIME_FORMAT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Formats a local time from a unix timestamp and a timezone offset (minutes
 * east of UTC) into a null-terminated string.
 *
 * `out_buf` must hold at least 8 bytes (e.g. "11:59 PM\0" or "23:59\0").
 * Returns the number of characters written (excluding the trailing NUL),
 * or 0 on failure.
 */
size_t host_sim_format_clock(int64_t unix_time,
                             int16_t tz_offset_minutes,
                             bool    is_24h,
                             char   *out_buf,
                             size_t  out_cap);

/* Formats a short weekday + date line for the secondary label below the
 * time, e.g. "Fri 31 Jan". `out_buf` must hold at least 16 bytes. */
size_t host_sim_format_date(int64_t unix_time,
                            int16_t tz_offset_minutes,
                            char   *out_buf,
                            size_t  out_cap);

#ifdef __cplusplus
}
#endif

#endif /* HOST_SIM_TIME_FORMAT_H */
