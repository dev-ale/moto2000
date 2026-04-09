/*
 * compass_layout.c — pure math helpers for the compass screen.
 *
 * No framebuffer access; everything here is trivially unit-testable.
 */
#include "compass_layout.h"

#include <math.h>

#include "ble_protocol.h"

uint16_t host_sim_compass_normalize_deg_x10(int32_t raw)
{
    const int32_t modulo = 3600;
    int32_t       v      = raw % modulo;
    if (v < 0) {
        v += modulo;
    }
    return (uint16_t)v;
}

uint16_t host_sim_compass_heading_to_whole_deg(uint16_t heading_deg_x10)
{
    /* Round half-up, then wrap 360 -> 0 so the readout never shows "360°". */
    const uint32_t rounded = ((uint32_t)heading_deg_x10 + 5U) / 10U;
    return (uint16_t)(rounded % 360U);
}

compass_point_t host_sim_compass_point_on_dial(uint16_t heading_deg_x10,
                                               uint16_t tick_deg_x10,
                                               int      cx,
                                               int      cy,
                                               int      radius)
{
    /*
     * The dial rotates so that the current heading sits at the top of the
     * screen. A tick at `tick_deg` is therefore drawn at screen-angle
     * `tick_deg - heading` measured clockwise from up.
     *
     * Convert to the standard math frame (angle from +x, counter-clockwise)
     * and build the point on the circle of radius `radius` centred on
     * (cx, cy). Screen y grows down so the vertical term is negated.
     */
    const int32_t relative_x10 =
        (int32_t)tick_deg_x10 - (int32_t)heading_deg_x10;
    const uint16_t screen_angle_x10 =
        host_sim_compass_normalize_deg_x10(relative_x10);
    const double theta_rad =
        ((double)screen_angle_x10 / 10.0) * (M_PI / 180.0);
    const double x_offset = sin(theta_rad) * (double)radius;
    const double y_offset = cos(theta_rad) * (double)radius;

    compass_point_t p;
    p.x = cx + (int)lround(x_offset);
    p.y = cy - (int)lround(y_offset);
    return p;
}

uint16_t host_sim_compass_displayed_heading_x10(uint16_t magnetic_deg_x10,
                                                uint16_t true_deg_x10,
                                                uint8_t  compass_flags)
{
    const bool want_true = (compass_flags & BLE_COMPASS_FLAG_USE_TRUE_HEADING) != 0U;
    if (want_true && true_deg_x10 != BLE_COMPASS_TRUE_HEADING_UNKNOWN) {
        return true_deg_x10;
    }
    return magnetic_deg_x10;
}
