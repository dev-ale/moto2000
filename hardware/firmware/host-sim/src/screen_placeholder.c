/*
 * screen_placeholder.c — "screen 0xNN pending" fallback.
 *
 * Any screen id that does not yet have a real renderer in Slice 1.5b
 * lands here. This keeps the simulator producing *something* so the
 * dispatch path can be exercised end-to-end before individual screen
 * slices land.
 */
#include "host_sim/renderer.h"
#include "text_draw.h"

#include <stdio.h>

void host_sim_render_placeholder(host_sim_canvas_t *canvas, uint8_t screen_id)
{
    host_sim_canvas_fill(canvas, 0x11, 0x11, 0x11);

    char line1[32];
    (void)snprintf(line1, sizeof(line1), "SCREEN 0x%02X", (unsigned)screen_id);
    const char *line2 = "PENDING";

    const int scale1 = 5;
    const int scale2 = 4;
    const int w1 = host_sim_measure_text(line1, scale1);
    const int w2 = host_sim_measure_text(line2, scale2);
    const int x1 = (canvas->width - w1) / 2;
    const int x2 = (canvas->width - w2) / 2;
    const int y1 = canvas->height / 2 - 8 * scale1;
    const int y2 = canvas->height / 2 + 20;

    host_sim_draw_text(canvas, line1, x1, y1, scale1, 0xCC, 0xCC, 0xCC);
    host_sim_draw_text(canvas, line2, x2, y2, scale2, 0x99, 0x99, 0x99);

    host_sim_canvas_apply_round_mask(canvas);
}
