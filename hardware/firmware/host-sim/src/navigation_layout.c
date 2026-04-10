/*
 * navigation_layout.c — pure formatting helpers for the navigation
 * screen. See navigation_layout.h for the contract.
 */
#include "host_sim/navigation_layout.h"

#include <stdio.h>
#include <string.h>

size_t host_sim_nav_format_distance(uint16_t meters, char *buf, size_t buf_len)
{
    if (buf == NULL || buf_len == 0U) {
        return 0U;
    }
    if (meters == HOST_SIM_NAV_UNKNOWN_U16) {
        if (buf_len < 3U) {
            buf[0] = '\0';
            return 0U;
        }
        buf[0] = '-';
        buf[1] = '-';
        buf[2] = '\0';
        return 2U;
    }
    int written;
    if (meters < 1000U) {
        written = snprintf(buf, buf_len, "%uM", (unsigned)meters);
    } else {
        /* 0.5KM, 1.2KM, ... 65KM. */
        const unsigned tenths = (unsigned)(meters / 100U); /* metres/100 = tenths of km */
        const unsigned whole = tenths / 10U;
        const unsigned frac = tenths % 10U;
        if (whole >= 100U) {
            written = snprintf(buf, buf_len, "%uKM", whole);
        } else {
            written = snprintf(buf, buf_len, "%u.%uKM", whole, frac);
        }
    }
    if (written < 0 || (size_t)written >= buf_len) {
        buf[0] = '\0';
        return 0U;
    }
    return (size_t)written;
}

size_t host_sim_nav_format_eta_line(uint16_t eta_minutes, uint16_t remaining_km_x10, char *buf,
                                    size_t buf_len)
{
    if (buf == NULL || buf_len == 0U) {
        return 0U;
    }
    char eta_part[12];
    char rem_part[12];

    if (eta_minutes == HOST_SIM_NAV_UNKNOWN_U16) {
        (void)snprintf(eta_part, sizeof(eta_part), "ETA --");
    } else {
        (void)snprintf(eta_part, sizeof(eta_part), "ETA %uM", (unsigned)eta_minutes);
    }

    if (remaining_km_x10 == HOST_SIM_NAV_UNKNOWN_U16) {
        (void)snprintf(rem_part, sizeof(rem_part), "REM --");
    } else {
        const unsigned whole = (unsigned)(remaining_km_x10 / 10U);
        const unsigned frac = (unsigned)(remaining_km_x10 % 10U);
        if (whole >= 100U) {
            (void)snprintf(rem_part, sizeof(rem_part), "REM %uKM", whole);
        } else {
            (void)snprintf(rem_part, sizeof(rem_part), "REM %u.%uKM", whole, frac);
        }
    }

    const int written = snprintf(buf, buf_len, "%s  %s", eta_part, rem_part);
    if (written < 0 || (size_t)written >= buf_len) {
        buf[0] = '\0';
        return 0U;
    }
    return (size_t)written;
}

host_sim_arrow_shape_t host_sim_nav_arrow_shape(ble_maneuver_t maneuver)
{
    switch (maneuver) {
    case BLE_MANEUVER_STRAIGHT:
    case BLE_MANEUVER_MERGE:
    case BLE_MANEUVER_NONE:
        return HOST_SIM_ARROW_STRAIGHT;
    case BLE_MANEUVER_SLIGHT_LEFT:
    case BLE_MANEUVER_LEFT:
    case BLE_MANEUVER_SHARP_LEFT:
        return HOST_SIM_ARROW_LEFT;
    case BLE_MANEUVER_SLIGHT_RIGHT:
    case BLE_MANEUVER_RIGHT:
    case BLE_MANEUVER_SHARP_RIGHT:
        return HOST_SIM_ARROW_RIGHT;
    case BLE_MANEUVER_U_TURN_LEFT:
        return HOST_SIM_ARROW_U_TURN_LEFT;
    case BLE_MANEUVER_U_TURN_RIGHT:
        return HOST_SIM_ARROW_U_TURN_RIGHT;
    case BLE_MANEUVER_ROUNDABOUT_ENTER:
    case BLE_MANEUVER_ROUNDABOUT_EXIT:
        return HOST_SIM_ARROW_ROUNDABOUT;
    case BLE_MANEUVER_FORK_LEFT:
        return HOST_SIM_ARROW_FORK_LEFT;
    case BLE_MANEUVER_FORK_RIGHT:
        return HOST_SIM_ARROW_FORK_RIGHT;
    case BLE_MANEUVER_ARRIVE:
        return HOST_SIM_ARROW_ARRIVE;
    }
    return HOST_SIM_ARROW_STRAIGHT;
}

void host_sim_nav_uppercase_clamp(const char *in, char *out, size_t max_len)
{
    if (out == NULL || max_len == 0U) {
        return;
    }
    if (in == NULL) {
        out[0] = '\0';
        return;
    }
    size_t i = 0U;
    while (in[i] != '\0' && i + 1U < max_len) {
        const char c = in[i];
        if (c >= 'a' && c <= 'z') {
            out[i] = (char)(c - ('a' - 'A'));
        } else {
            out[i] = c;
        }
        ++i;
    }
    out[i] = '\0';
}
