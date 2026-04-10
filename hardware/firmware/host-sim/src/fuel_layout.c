/*
 * fuel_layout.c — pure helpers for the fuel estimate screen.
 */
#include "fuel_layout.h"

#include <stdio.h>

void format_tank_percent(uint8_t pct, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0U) {
        return;
    }
    (void)snprintf(buf, buf_len, "%u%%", (unsigned)pct);
}

void format_range(uint16_t km, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0U) {
        return;
    }
    if (km == FUEL_UNKNOWN_U16) {
        (void)snprintf(buf, buf_len, "-- KM");
    } else {
        (void)snprintf(buf, buf_len, "%u KM", (unsigned)km);
    }
}

void format_consumption(uint16_t ml_per_km, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0U) {
        return;
    }
    if (ml_per_km == FUEL_UNKNOWN_U16) {
        (void)snprintf(buf, buf_len, "-- ML/KM");
    } else {
        (void)snprintf(buf, buf_len, "%u ML/KM", (unsigned)ml_per_km);
    }
}

void format_fuel_remaining(uint16_t ml, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0U) {
        return;
    }
    if (ml == FUEL_UNKNOWN_U16) {
        (void)snprintf(buf, buf_len, "-- L");
    } else {
        /* Convert mL to L with one decimal. Integer division for the
         * whole part and modulus for the fractional part avoids pulling
         * in floating-point printf on constrained targets. */
        const unsigned whole = (unsigned)ml / 1000U;
        const unsigned frac  = ((unsigned)ml % 1000U) / 100U;
        (void)snprintf(buf, buf_len, "%u.%u L", whole, frac);
    }
}

int fuel_bar_fill(uint8_t pct, int bar_height)
{
    if (bar_height <= 0) {
        return 0;
    }
    if (pct > 100) {
        pct = 100;
    }
    return (int)((long)pct * (long)bar_height / 100L);
}
