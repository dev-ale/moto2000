/*
 * trip_stats_layout.h — pure-C layout helpers for the Trip Stats screen.
 *
 * Like speed_layout / compass_layout, kept free of any canvas / SDL /
 * PNG dependency so the formatting and rounding logic can be exercised
 * with Unity host tests.
 */
#ifndef HOST_SIM_TRIP_STATS_LAYOUT_H
#define HOST_SIM_TRIP_STATS_LAYOUT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Format the hero distance readout. Switching rule:
 *   - Below 1 000 m: "<n> M"   (e.g. "950 M",  "0 M")
 *   - 1 000 m to 99 999 m: "<n.n> KM" (one decimal, e.g. "7.4 KM", "12.3 KM")
 *   - 100 000 m and above: "<n> KM" (no decimal, e.g. "127 KM", "1234 KM")
 *
 * `buf` needs >= 12 bytes. Returns strlen on success or 0 on overflow.
 */
size_t host_sim_format_distance(uint32_t meters, char *buf, size_t buf_len);

/*
 * Format an elapsed duration. Returns:
 *   - "MM:SS" if seconds < 3600 (e.g. "00:00", "24:17")
 *   - "H:MM:SS" if seconds >= 3600 (e.g. "1:24:17")
 * Hours are clamped to 99 to keep the buffer bounded.
 *
 * `buf` needs >= 12 bytes. Returns strlen on success or 0 on overflow.
 */
size_t host_sim_format_duration(uint32_t seconds, char *buf, size_t buf_len);

/*
 * Format an average / max speed cell, e.g. "AVG 42 KM/H" or "MAX 68 KM/H".
 * `prefix` must be a 3-char ASCII tag ("AVG" or "MAX"). Speed is in
 * km/h × 10 (matching the wire format) and rounded half-up.
 *
 * `buf` needs >= 16 bytes. Returns strlen on success or 0 on overflow.
 */
size_t host_sim_format_speed_cell(const char *prefix,
                                  uint16_t    speed_kmh_x10,
                                  char       *buf,
                                  size_t      buf_len);

/*
 * Format an ascent or descent value. Pass `is_descent = false` for
 * ascent (renders "+120M"), `true` for descent (renders "-120M").
 * Values are clamped to the uint16 range that the wire format provides.
 *
 * `buf` needs >= 8 bytes. Returns strlen on success or 0 on overflow.
 */
size_t host_sim_format_elevation_delta(uint16_t meters,
                                       int      is_descent,
                                       char    *buf,
                                       size_t   buf_len);

#ifdef __cplusplus
}
#endif

#endif /* HOST_SIM_TRIP_STATS_LAYOUT_H */
