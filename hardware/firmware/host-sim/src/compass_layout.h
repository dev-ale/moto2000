/*
 * compass_layout.h — pure math helpers for the compass screen.
 *
 * Kept as a separate unit so the trigonometry that places tick marks,
 * cardinal labels and the needle on the round canvas can be unit-tested
 * under Unity without touching the framebuffer or PNG writer.
 *
 * Angle convention:
 *   heading_deg_x10 is the current heading in tenths of a degree,
 *   0 = north. On a rotating-dial compass the dial is rotated so that the
 *   current heading sits at the top of the screen, i.e. each tick at
 *   `tick_deg` on the rose is drawn at screen-angle `tick_deg - heading`,
 *   where 0° is straight up and angle grows clockwise.
 *
 * Coordinate frame: screen x grows right, y grows down.
 */
#ifndef HOST_SIM_COMPASS_LAYOUT_H
#define HOST_SIM_COMPASS_LAYOUT_H

#include <stdint.h>

typedef struct {
    int x;
    int y;
} compass_point_t;

/*
 * Compute the screen-space position of a feature sitting on the dial at
 * `tick_deg_x10` when the dial is currently rotated so that `heading_deg_x10`
 * is at the top. `cx`,`cy` is the dial centre and `radius` is the distance
 * from the centre in pixels.
 */
compass_point_t host_sim_compass_point_on_dial(uint16_t heading_deg_x10,
                                               uint16_t tick_deg_x10,
                                               int      cx,
                                               int      cy,
                                               int      radius);

/*
 * Normalise an arbitrary heading-in-tenths-of-a-degree into the canonical
 * `0..=3599` range. Wraps negative and > 3600 values.
 */
uint16_t host_sim_compass_normalize_deg_x10(int32_t raw);

/*
 * Round a tenths-of-a-degree heading to its nearest whole degree (0..=359),
 * used for the digital readout.
 */
uint16_t host_sim_compass_heading_to_whole_deg(uint16_t heading_deg_x10);

/*
 * Pick which heading to render based on the compass flags and the raw
 * body. Returns the magnetic value when the true-heading flag is not set
 * or when the true heading is the 0xFFFF unknown sentinel.
 */
uint16_t host_sim_compass_displayed_heading_x10(uint16_t magnetic_deg_x10,
                                                uint16_t true_deg_x10,
                                                uint8_t  compass_flags);

#endif /* HOST_SIM_COMPASS_LAYOUT_H */
