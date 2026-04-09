/*
 * main.c — scramscreen-host-sim entry point.
 *
 * Usage:
 *   scramscreen-host-sim --out path.png [--in path.bin]
 *
 * If --in is not given, reads the raw BLE payload from stdin until EOF.
 * On success, writes a PNG snapshot of the rendered screen to --out and
 * exits with status 0.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "host_sim/renderer.h"

#define MAX_PAYLOAD 4096U

static int read_all(FILE *f, uint8_t *buf, size_t cap, size_t *out_len)
{
    size_t total = 0;
    while (total < cap) {
        const size_t got = fread(buf + total, 1, cap - total, f);
        if (got == 0) {
            if (feof(f)) {
                break;
            }
            return 1;
        }
        total += got;
    }
    *out_len = total;
    return 0;
}

static void usage(FILE *out)
{
    fputs(
        "Usage: scramscreen-host-sim --out PATH [--in PATH]\n"
        "\n"
        "Reads a BLE payload (same wire format as the firmware\n"
        "characteristic) from --in or stdin, renders the corresponding\n"
        "ScramScreen screen to a 466x466 PNG, and writes it to --out.\n",
        out);
}

int main(int argc, char **argv)
{
    const char *out_path = NULL;
    const char *in_path  = NULL;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) {
            out_path = argv[++i];
        } else if (strcmp(argv[i], "--in") == 0 && i + 1 < argc) {
            in_path = argv[++i];
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(stdout);
            return 0;
        } else {
            fprintf(stderr, "unknown argument: %s\n", argv[i]);
            usage(stderr);
            return 2;
        }
    }
    if (out_path == NULL) {
        fprintf(stderr, "missing --out\n");
        usage(stderr);
        return 2;
    }

    uint8_t payload[MAX_PAYLOAD];
    size_t  payload_len = 0;
    FILE   *in          = NULL;
    if (in_path != NULL) {
        in = fopen(in_path, "rb");
        if (in == NULL) {
            fprintf(stderr, "cannot open %s\n", in_path);
            return 3;
        }
    } else {
        in = stdin;
    }
    if (read_all(in, payload, sizeof(payload), &payload_len) != 0) {
        fprintf(stderr, "failed to read payload\n");
        if (in != stdin) {
            fclose(in);
        }
        return 4;
    }
    if (in != stdin) {
        fclose(in);
    }
    if (payload_len == 0) {
        fprintf(stderr, "empty payload\n");
        return 5;
    }

    host_sim_canvas_t *canvas = host_sim_canvas_create();
    if (canvas == NULL) {
        fprintf(stderr, "out of memory\n");
        return 6;
    }
    const int render_rc = host_sim_render_payload(canvas, payload, payload_len);
    const int write_rc  = host_sim_canvas_write_png(canvas, out_path);
    host_sim_canvas_destroy(canvas);

    if (write_rc != 0) {
        fprintf(stderr, "failed to write PNG to %s\n", out_path);
        return 7;
    }
    return render_rc == 0 ? 0 : 10 + render_rc;
}
