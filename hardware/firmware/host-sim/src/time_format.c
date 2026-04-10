/*
 * time_format.c — deterministic clock/date formatting.
 *
 * Uses a custom unix→Y/M/D conversion (Howard Hinnant's civil_from_days)
 * so the output does NOT depend on the host's zoneinfo, locale, or TZ env
 * var. Every CI runner must produce byte-identical output given the same
 * inputs or snapshot tests will flap.
 */
#include "host_sim/time_format.h"

#include <stdio.h>

static void civil_from_days(int64_t days, int32_t *out_year, uint32_t *out_month, uint32_t *out_day)
{
    /* Algorithm from http://howardhinnant.github.io/date_algorithms.html
     * "civil_from_days". Valid for any reasonable date range. */
    days += 719468;
    const int64_t era = (days >= 0 ? days : days - 146096) / 146097;
    const uint32_t doe = (uint32_t)(days - era * 146097);
    const uint32_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const int32_t y = (int32_t)yoe + (int32_t)(era * 400);
    const uint32_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const uint32_t mp = (5 * doy + 2) / 153;
    const uint32_t d = doy - (153 * mp + 2) / 5 + 1;
    const uint32_t m = mp < 10 ? mp + 3 : mp - 9;
    *out_year = y + (m <= 2 ? 1 : 0);
    *out_month = m;
    *out_day = d;
}

/* Returns weekday 0..6 with 0=Sunday, computed directly from days-since-epoch. */
static uint32_t weekday_from_days(int64_t days)
{
    /* 1970-01-01 was a Thursday = 4 (Sun=0). */
    int64_t w = (days + 4) % 7;
    if (w < 0) {
        w += 7;
    }
    return (uint32_t)w;
}

size_t host_sim_format_clock(int64_t unix_time, int16_t tz_offset_minutes, bool is_24h,
                             char *out_buf, size_t out_cap)
{
    if (out_buf == NULL || out_cap < 8) {
        return 0;
    }
    const int64_t local_seconds = unix_time + (int64_t)tz_offset_minutes * 60;
    int64_t seconds_of_day = local_seconds % 86400;
    if (seconds_of_day < 0) {
        seconds_of_day += 86400;
    }
    const int hour24 = (int)(seconds_of_day / 3600);
    const int minute = (int)((seconds_of_day / 60) % 60);

    int n;
    if (is_24h) {
        n = snprintf(out_buf, out_cap, "%02d:%02d", hour24, minute);
    } else {
        int hour12 = hour24 % 12;
        if (hour12 == 0) {
            hour12 = 12;
        }
        const char *suffix = (hour24 < 12) ? "AM" : "PM";
        n = snprintf(out_buf, out_cap, "%d:%02d %s", hour12, minute, suffix);
    }
    if (n < 0) {
        return 0;
    }
    return (size_t)n;
}

size_t host_sim_format_date(int64_t unix_time, int16_t tz_offset_minutes, char *out_buf,
                            size_t out_cap)
{
    if (out_buf == NULL || out_cap < 16) {
        return 0;
    }
    const int64_t local_seconds = unix_time + (int64_t)tz_offset_minutes * 60;
    int64_t days = local_seconds / 86400;
    int64_t seconds_of_day = local_seconds % 86400;
    if (seconds_of_day < 0) {
        days -= 1;
    }
    int32_t year = 0;
    uint32_t month = 0;
    uint32_t day = 0;
    civil_from_days(days, &year, &month, &day);
    const uint32_t wday = weekday_from_days(days);

    static const char *const wday_names[7] = {
        "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",
    };
    static const char *const month_names[12] = {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    };

    const int n = snprintf(out_buf, out_cap, "%s %u %s", wday_names[wday], (unsigned)day,
                           month_names[month - 1]);
    if (n < 0) {
        return 0;
    }
    /* silence unused-but-set warning on some compilers */
    (void)year;
    return (size_t)n;
}
