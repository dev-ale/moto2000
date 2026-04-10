/*
 * music_layout.h — pure-C formatting helpers for the music screen.
 *
 * Split from screen_music.c so the logic can be unit-tested under Unity
 * without dragging in the canvas / font / renderer stack. Every helper
 * is deterministic and does not allocate.
 */
#ifndef HOST_SIM_MUSIC_LAYOUT_H
#define HOST_SIM_MUSIC_LAYOUT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Sentinel for unknown position or duration. Matches MusicData on the wire. */
#define HOST_SIM_MUSIC_UNKNOWN_U16 ((uint16_t)0xFFFFU)

/*
 * Compute the pixel fill width for the progress bar.
 *
 *   position == 0xFFFF or duration == 0xFFFF → returns -1 (indeterminate)
 *   duration == 0                             → returns 0
 *   position >= duration                      → returns bar_width
 *   otherwise                                 → returns (position / duration) * bar_width
 *
 * `bar_width` must be non-negative.
 */
int host_sim_music_progress_fill_width(uint16_t position_seconds,
                                       uint16_t duration_seconds,
                                       int      bar_width);

/*
 * Truncate ASCII `in` into `out` with trailing ".." if it would overflow.
 *
 * - `out_len` must be at least 3 (one char + ".." + NUL would need 4, but
 *   we allow 3 to produce "..\0" for very small buffers).
 * - If `strlen(in)` already fits in `out_len - 1` bytes, copies verbatim.
 * - Otherwise truncates to `out_len - 3` characters and appends "..\0".
 *
 * Returns the number of bytes written excluding the terminator.
 */
size_t host_sim_music_truncate_with_ellipsis(const char *in,
                                             char       *out,
                                             size_t      out_len);

/*
 * Uppercase-in-place up to `out_len - 1` bytes and NUL-terminate. The
 * bundled 8x8 font is uppercase-only ASCII. Input and output may alias.
 */
void host_sim_music_uppercase_ascii(const char *in,
                                    char       *out,
                                    size_t      out_len);

/*
 * Format a `M:SS` or `MM:SS` time string into `buf`.
 *
 *   seconds == 0xFFFF → "--:--"
 *   otherwise         → "1:24", "12:34", "65:00", ...
 *
 * Returns the number of bytes written excluding the terminator, or 0 on
 * buffer-too-small. A 12-byte buffer is always enough.
 */
size_t host_sim_music_format_time(uint16_t seconds,
                                  char    *buf,
                                  size_t   buf_len);

#ifdef __cplusplus
}
#endif

#endif /* HOST_SIM_MUSIC_LAYOUT_H */
