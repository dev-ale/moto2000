/*
 * text_draw.h — internal helper for drawing scaled bitmap text onto a
 * host_sim_canvas_t. Not part of the public host_sim API.
 */
#ifndef HOST_SIM_TEXT_DRAW_H
#define HOST_SIM_TEXT_DRAW_H

#include <stddef.h>
#include <stdint.h>

#include "host_sim/renderer.h"

void host_sim_draw_text(host_sim_canvas_t *canvas, const char *text, int origin_x, int origin_y,
                        int scale, uint8_t r, uint8_t g, uint8_t b);

/* Measures pixel width of `text` at scale `scale` for a monospace 8px font. */
int host_sim_measure_text(const char *text, int scale);

#endif /* HOST_SIM_TEXT_DRAW_H */
