/*
 * screen_appointment.c — renders the appointment screen onto the round
 * 466x466 panel.
 *
 * Layout:
 *   - Background: navy in day mode, black in night mode.
 *   - Hero: time-until in large text — "IN 30M", "NOW", "15M AGO".
 *   - Title: below hero, medium text, uppercase.
 *   - Location: below title, small muted text, uppercase.
 *   - Night mode: red palette.
 */
#include "host_sim/renderer.h"
#include "host_sim/appointment_layout.h"
#include "text_draw.h"

#include <string.h>

#include "ble_protocol.h"

void host_sim_render_appointment(host_sim_canvas_t *canvas,
                                 const ble_appointment_data_t *appointment, uint8_t header_flags)
{
    const bool night = (header_flags & BLE_FLAG_NIGHT_MODE) != 0U;
    if (night) {
        host_sim_canvas_fill(canvas, 0, 0, 0);
    } else {
        host_sim_canvas_fill(canvas, 0x0A, 0x1C, 0x3A);
    }

    const uint8_t text_r = night ? 0x88U : 0xFFU;
    const uint8_t text_g = night ? 0x11U : 0xFFU;
    const uint8_t text_b = night ? 0x11U : 0xFFU;

    /* Muted text for location. */
    const uint8_t muted_r = night ? 0x55U : 0xAAU;
    const uint8_t muted_g = night ? 0x00U : 0xAAU;
    const uint8_t muted_b = night ? 0x00U : 0xAAU;

    const int cx = canvas->width / 2;

    /* Hero: "IN 30M" / "NOW" / "15M AGO" */
    char hero[16] = { 0 };
    host_sim_appointment_format_starts_in(appointment->starts_in_minutes, hero, sizeof(hero));
    const int hero_scale = 7;
    const int hero_w = host_sim_measure_text(hero, hero_scale);
    const int hero_h = 8 * hero_scale;
    const int hero_y = 150;
    host_sim_draw_text(canvas, hero, cx - hero_w / 2, hero_y, hero_scale, text_r, text_g, text_b);

    /* Title: uppercase, medium text. */
    char title[APPOINTMENT_LAYOUT_MAX_TITLE_CHARS + 1] = { 0 };
    host_sim_appointment_uppercase_title(appointment->title, title, sizeof(title));
    const int title_scale = 3;
    const int title_w = host_sim_measure_text(title, title_scale);
    const int title_y = hero_y + hero_h + 24;
    host_sim_draw_text(canvas, title, cx - title_w / 2, title_y, title_scale, text_r, text_g,
                       text_b);

    /* Location: uppercase, small muted text. */
    char loc[APPOINTMENT_LAYOUT_MAX_LOCATION_CHARS + 1] = { 0 };
    host_sim_appointment_uppercase_location(appointment->location, loc, sizeof(loc));
    const int loc_scale = 2;
    const int loc_w = host_sim_measure_text(loc, loc_scale);
    const int loc_y = title_y + 8 * title_scale + 16;
    host_sim_draw_text(canvas, loc, cx - loc_w / 2, loc_y, loc_scale, muted_r, muted_g, muted_b);

    host_sim_canvas_apply_round_mask(canvas);
}
