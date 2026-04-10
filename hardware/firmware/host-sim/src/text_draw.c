/*
 * text_draw.c — scaled 8x8 bitmap text blitter.
 */
#include "text_draw.h"

#include <string.h>

#include "font8x8.h"

static void put_pixel(host_sim_canvas_t *canvas, int x, int y, uint8_t r, uint8_t g, uint8_t b)
{
    if (x < 0 || y < 0 || x >= canvas->width || y >= canvas->height) {
        return;
    }
    const size_t idx = ((size_t)y * (size_t)canvas->width + (size_t)x) * 3U;
    canvas->pixels[idx + 0U] = r;
    canvas->pixels[idx + 1U] = g;
    canvas->pixels[idx + 2U] = b;
}

void host_sim_draw_text(host_sim_canvas_t *canvas, const char *text, int origin_x, int origin_y,
                        int scale, uint8_t r, uint8_t g, uint8_t b)
{
    if (canvas == NULL || text == NULL || scale <= 0) {
        return;
    }
    int x_cursor = origin_x;
    for (const char *p = text; *p != '\0'; ++p) {
        const uint8_t *glyph = font8x8_glyph(*p);
        for (int row = 0; row < 8; ++row) {
            const uint8_t bits = glyph[row];
            for (int col = 0; col < 8; ++col) {
                if ((bits & (0x80U >> (unsigned)col)) == 0U) {
                    continue;
                }
                for (int sy = 0; sy < scale; ++sy) {
                    for (int sx = 0; sx < scale; ++sx) {
                        put_pixel(canvas, x_cursor + col * scale + sx, origin_y + row * scale + sy,
                                  r, g, b);
                    }
                }
            }
        }
        x_cursor += 8 * scale;
    }
}

int host_sim_measure_text(const char *text, int scale)
{
    if (text == NULL || scale <= 0) {
        return 0;
    }
    return (int)strlen(text) * 8 * scale;
}
