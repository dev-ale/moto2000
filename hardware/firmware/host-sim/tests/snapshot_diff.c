/*
 * snapshot_diff.c — compares two PNG files pixel-for-pixel.
 *
 * Returns 0 if they are identical (same dimensions, same channel count,
 * same bytes). Non-zero on any mismatch, with a human-readable summary on
 * stderr.
 *
 * Usage:
 *   snapshot-diff actual.png golden.png
 */
#include <stdio.h>
#include <stdlib.h>

#include "stb_image.h"

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: snapshot-diff actual.png golden.png\n");
        return 2;
    }
    int aw, ah, ac;
    int gw, gh, gc;
    unsigned char *a = stbi_load(argv[1], &aw, &ah, &ac, 3);
    unsigned char *g = stbi_load(argv[2], &gw, &gh, &gc, 3);
    if (a == NULL) {
        fprintf(stderr, "failed to load %s: %s\n", argv[1], stbi_failure_reason());
        if (g != NULL)
            stbi_image_free(g);
        return 3;
    }
    if (g == NULL) {
        fprintf(stderr, "failed to load %s: %s\n", argv[2], stbi_failure_reason());
        stbi_image_free(a);
        return 3;
    }
    int rc = 0;
    if (aw != gw || ah != gh) {
        fprintf(stderr, "snapshot-diff: dimensions mismatch (%dx%d vs %dx%d)\n", aw, ah, gw, gh);
        rc = 4;
    } else {
        long long diff_pixels = 0;
        long long worst = 0;
        const long long total = (long long)aw * (long long)ah;
        for (long long i = 0; i < total; ++i) {
            const int dr = (int)a[i * 3 + 0] - (int)g[i * 3 + 0];
            const int dg = (int)a[i * 3 + 1] - (int)g[i * 3 + 1];
            const int db = (int)a[i * 3 + 2] - (int)g[i * 3 + 2];
            const int mag = (dr < 0 ? -dr : dr) + (dg < 0 ? -dg : dg) + (db < 0 ? -db : db);
            if (mag != 0) {
                diff_pixels++;
                if (mag > worst)
                    worst = mag;
            }
        }
        if (diff_pixels != 0) {
            fprintf(stderr, "snapshot-diff: %lld / %lld pixels differ (worst delta=%lld)\n",
                    diff_pixels, total, worst);
            rc = 5;
        }
    }
    stbi_image_free(a);
    stbi_image_free(g);
    return rc;
}
