/*
 * altitude_layout.h — pure helpers for the altitude profile screen.
 *
 * Coordinate mapping functions for the elevation line graph and text
 * formatting for altitude labels.
 */
#ifndef HOST_SIM_ALTITUDE_LAYOUT_H
#define HOST_SIM_ALTITUDE_LAYOUT_H

#include <stddef.h>
#include <stdint.h>

#include "host_sim/renderer.h"

/*
 * Map an altitude value to a pixel Y coordinate within the graph area.
 * graph_top is the Y coordinate of the top of the graph (low Y = high pixel).
 * graph_bottom is the Y coordinate of the bottom.
 * Returns graph_bottom when altitude == min_alt, graph_top when altitude == max_alt.
 * Clamps to the graph area bounds.
 */
int altitude_graph_y(int16_t altitude, int16_t min_alt, int16_t max_alt,
                     int graph_top, int graph_bottom);

/*
 * Map a sample index to a pixel X coordinate within the graph area.
 * Returns graph_left when sample_index == 0,
 * graph_right when sample_index == sample_count - 1.
 */
int altitude_graph_x(int sample_index, int sample_count,
                     int graph_left, int graph_right);

/*
 * Format an altitude label: "260M" / "-50M" / "2400M".
 * buf_len must be at least 8.
 */
void format_altitude_label(int16_t meters, char *buf, size_t buf_len);

/*
 * Format ascent/descent: "+1900M" / "-600M".
 * buf_len must be at least 10.
 */
void format_altitude_delta(int16_t meters, int is_ascent, char *buf, size_t buf_len);

/*
 * Draw a line between two points using Bresenham's algorithm.
 * Clips to canvas bounds.
 */
void draw_line(host_sim_canvas_t *canvas,
               int x0, int y0, int x1, int y1,
               uint8_t r, uint8_t g, uint8_t b);

#endif /* HOST_SIM_ALTITUDE_LAYOUT_H */
