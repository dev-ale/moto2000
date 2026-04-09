/*
 * navigation_layout.h — pure-C formatting helpers for the navigation
 * screen. Split from screen_navigation.c so the logic can be unit-tested
 * under Unity without dragging in the canvas / font / renderer stack.
 *
 * All helpers are deterministic and do not allocate. Every formatter
 * takes an output buffer + capacity, returns the number of bytes
 * written (excluding the NUL), and returns 0 if the buffer is too
 * small.
 */
#ifndef HOST_SIM_NAVIGATION_LAYOUT_H
#define HOST_SIM_NAVIGATION_LAYOUT_H

#include <stddef.h>
#include <stdint.h>

#include "ble_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Sentinel used on the wire for "unknown distance". Matches NavData. */
#define HOST_SIM_NAV_UNKNOWN_U16 ((uint16_t)0xFFFFU)

/*
 * Format the big distance-to-next-maneuver readout.
 *
 *   meters < 1000  → "320M"
 *   meters >= 1000 → "0.5KM", "1.2KM", "12KM"
 *   meters == 0xFFFF → "--"
 *
 * Writes a NUL-terminated ASCII string into `buf`. Returns the number of
 * bytes written excluding the terminator, or 0 if `buf_len` is too
 * small. The longest possible output is "999KM\0" (6 bytes), so an
 * 8-byte buffer is always enough.
 */
size_t host_sim_nav_format_distance(uint16_t meters,
                                    char    *buf,
                                    size_t   buf_len);

/*
 * Format the bottom status line: "ETA 18M  REM 7.4KM".
 *
 *   eta_minutes == 0xFFFF     → "ETA --"
 *   remaining_km_x10 == 0xFFFF → "REM --"
 *
 * Otherwise minutes are printed as-is and remaining distance is divided
 * by 10 and printed with one decimal place (or no decimal above 100km).
 *
 * Returns the number of bytes written excluding the terminator, or 0
 * on buffer-too-small. A 32-byte buffer is always enough.
 */
size_t host_sim_nav_format_eta_line(uint16_t eta_minutes,
                                    uint16_t remaining_km_x10,
                                    char    *buf,
                                    size_t   buf_len);

/*
 * Maneuver → arrow glyph family. Kept intentionally coarse so the
 * renderer only needs to know how to draw ~6 arrow shapes: straight,
 * left, right, u-turn-left, u-turn-right, roundabout, arrive, fork.
 */
typedef enum {
    HOST_SIM_ARROW_STRAIGHT     = 0,
    HOST_SIM_ARROW_LEFT         = 1,
    HOST_SIM_ARROW_RIGHT        = 2,
    HOST_SIM_ARROW_U_TURN_LEFT  = 3,
    HOST_SIM_ARROW_U_TURN_RIGHT = 4,
    HOST_SIM_ARROW_ROUNDABOUT   = 5,
    HOST_SIM_ARROW_ARRIVE       = 6,
    HOST_SIM_ARROW_FORK_LEFT    = 7,
    HOST_SIM_ARROW_FORK_RIGHT   = 8,
} host_sim_arrow_shape_t;

/* Map a BLE maneuver enum to an arrow shape. Unknown / none → straight. */
host_sim_arrow_shape_t host_sim_nav_arrow_shape(ble_maneuver_t maneuver);

/*
 * Uppercase-in-place up to `max_len` bytes and NUL-terminate. Used to
 * normalise street names for the uppercase-only bundled font. Input
 * and output may alias.
 */
void host_sim_nav_uppercase_clamp(const char *in,
                                  char       *out,
                                  size_t      max_len);

#ifdef __cplusplus
}
#endif

#endif /* HOST_SIM_NAVIGATION_LAYOUT_H */
