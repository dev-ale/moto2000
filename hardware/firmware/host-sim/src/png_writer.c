/*
 * png_writer.c — wraps stb_image_write.h to emit a deterministic PNG
 * from a host_sim_canvas_t.
 */
#include "host_sim/renderer.h"

#include "stb_image_write.h"

int host_sim_canvas_write_png(const host_sim_canvas_t *canvas, const char *path)
{
    if (canvas == NULL || canvas->pixels == NULL || path == NULL) {
        return 1;
    }
    const int stride = canvas->width * 3;
    const int rc = stbi_write_png(path,
                                  canvas->width,
                                  canvas->height,
                                  3,
                                  canvas->pixels,
                                  stride);
    return rc == 0 ? 2 : 0;
}
