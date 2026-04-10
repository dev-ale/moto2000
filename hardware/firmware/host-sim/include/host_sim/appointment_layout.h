/*
 * appointment_layout.h — pure-C formatting helpers for the appointment screen.
 *
 * Split from screen_appointment.c so the logic can be unit-tested under
 * Unity without dragging in the canvas / font / renderer stack.
 */
#ifndef HOST_SIM_APPOINTMENT_LAYOUT_H
#define HOST_SIM_APPOINTMENT_LAYOUT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Maximum display length for the appointment title after uppercasing. */
#define APPOINTMENT_LAYOUT_MAX_TITLE_CHARS 20

/* Maximum display length for the location. */
#define APPOINTMENT_LAYOUT_MAX_LOCATION_CHARS 16

/*
 * Format the "starts in" hero text from minutes.
 *
 * Examples:
 *   30   → "IN 30M"
 *   0    → "NOW"
 *   -15  → "15M AGO"
 *   90   → "IN 90M"
 *   -120 → "120M AGO"
 *
 * `buf_len` must be at least 16.
 */
void host_sim_appointment_format_starts_in(int16_t minutes,
                                           char   *buf,
                                           size_t  buf_len);

/*
 * Uppercase a title and truncate to APPOINTMENT_LAYOUT_MAX_TITLE_CHARS.
 * ASCII-only (same as weather_layout).
 *
 * `out_len` must be at least APPOINTMENT_LAYOUT_MAX_TITLE_CHARS + 1.
 */
void host_sim_appointment_uppercase_title(const char *in,
                                          char       *out,
                                          size_t      out_len);

/*
 * Uppercase a location and truncate to APPOINTMENT_LAYOUT_MAX_LOCATION_CHARS.
 *
 * `out_len` must be at least APPOINTMENT_LAYOUT_MAX_LOCATION_CHARS + 1.
 */
void host_sim_appointment_uppercase_location(const char *in,
                                             char       *out,
                                             size_t      out_len);

#ifdef __cplusplus
}
#endif

#endif /* HOST_SIM_APPOINTMENT_LAYOUT_H */
