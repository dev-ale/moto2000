/*
 * screen_music.c — renders the music screen onto the round 466x466 panel.
 *
 * Layout:
 *   - Background: navy in day mode, black in night mode.
 *   - Album-art placeholder: a rounded-rectangle frame around 80x80 px
 *     in the upper-center area containing a stylised "music note" glyph
 *     (quarter note with a tail). Since BLE payloads do not carry album
 *     art, this is always rendered — Apple Music's empty-art placeholder
 *     is the design cue.
 *   - Title: large text below the album art, truncated with ".." if it
 *     overflows the canvas width, uppercased for the ASCII-only font.
 *   - Artist: smaller, slightly dimmer, below the title.
 *   - Album: smaller still, dimmer, below the artist.
 *   - Progress bar: horizontal near the bottom. Fill width is computed
 *     from position/duration; unknown sentinels render as a dashed bar.
 *   - Play/pause icon: tiny, corner-top-right.
 *   - Night mode: red palette matching every other screen.
 */
#include "host_sim/renderer.h"
#include "host_sim/music_layout.h"
#include "text_draw.h"

#include <stdio.h>
#include <string.h>

#include "ble_protocol.h"

static void put_pixel(host_sim_canvas_t *canvas, int x, int y,
                      uint8_t r, uint8_t g, uint8_t b)
{
    if (x < 0 || y < 0 || x >= canvas->width || y >= canvas->height) {
        return;
    }
    const size_t idx = ((size_t)y * (size_t)canvas->width + (size_t)x) * 3U;
    canvas->pixels[idx + 0U] = r;
    canvas->pixels[idx + 1U] = g;
    canvas->pixels[idx + 2U] = b;
}

static void fill_rect(host_sim_canvas_t *canvas,
                      int x0, int y0, int w, int h,
                      uint8_t r, uint8_t g, uint8_t b)
{
    for (int y = y0; y < y0 + h; ++y) {
        for (int x = x0; x < x0 + w; ++x) {
            put_pixel(canvas, x, y, r, g, b);
        }
    }
}

static void stroke_rect(host_sim_canvas_t *canvas,
                        int x0, int y0, int w, int h, int thickness,
                        uint8_t r, uint8_t g, uint8_t b)
{
    fill_rect(canvas, x0,             y0,             w,         thickness, r, g, b);
    fill_rect(canvas, x0,             y0 + h - thickness, w,     thickness, r, g, b);
    fill_rect(canvas, x0,             y0,             thickness, h,         r, g, b);
    fill_rect(canvas, x0 + w - thickness, y0,         thickness, h,         r, g, b);
}

/* A stylised quarter-note glyph: a filled oval head with a vertical stem
 * and a single tail/flag at the top. Drawn relative to `cx,cy`, sized to
 * fit inside a roughly `size`-pixel bounding box. */
static void draw_music_note(host_sim_canvas_t *canvas,
                            int cx, int cy, int size,
                            uint8_t r, uint8_t g, uint8_t b)
{
    const int head_rx = size / 4;
    const int head_ry = size / 6;
    const int head_cx = cx - size / 6;
    const int head_cy = cy + size / 4;
    for (int y = -head_ry; y <= head_ry; ++y) {
        for (int x = -head_rx; x <= head_rx; ++x) {
            /* Ellipse: (x/rx)^2 + (y/ry)^2 <= 1 */
            const int lhs = (x * x) * (head_ry * head_ry) + (y * y) * (head_rx * head_rx);
            const int rhs = (head_rx * head_rx) * (head_ry * head_ry);
            if (lhs <= rhs) {
                put_pixel(canvas, head_cx + x, head_cy + y, r, g, b);
            }
        }
    }
    /* Stem: vertical bar from head top up to the top of the glyph. */
    const int stem_x0 = head_cx + head_rx - 2;
    const int stem_y0 = cy - size / 2;
    const int stem_h  = (head_cy - head_ry + 2) - stem_y0;
    fill_rect(canvas, stem_x0, stem_y0, 3, stem_h, r, g, b);
    /* Flag: short diagonal from stem top. */
    const int flag_w = size / 3;
    const int flag_h = size / 6;
    fill_rect(canvas, stem_x0 + 3, stem_y0, flag_w, 3, r, g, b);
    fill_rect(canvas, stem_x0 + 3 + flag_w - 3, stem_y0, 3, flag_h, r, g, b);
}

static void draw_play_pause_icon(host_sim_canvas_t *canvas,
                                 int cx, int cy, bool playing,
                                 uint8_t r, uint8_t g, uint8_t b)
{
    if (playing) {
        /* Right-pointing triangle. */
        const int size = 14;
        for (int y = -size; y <= size; ++y) {
            const int half_width = size - (y < 0 ? -y : y);
            for (int x = 0; x <= half_width; ++x) {
                put_pixel(canvas, cx + x - size / 2, cy + y, r, g, b);
            }
        }
    } else {
        /* Two vertical bars. */
        fill_rect(canvas, cx - 8, cy - 12, 5, 24, r, g, b);
        fill_rect(canvas, cx + 3, cy - 12, 5, 24, r, g, b);
    }
}

static void draw_progress_bar(host_sim_canvas_t *canvas,
                              int x0, int y0, int width, int height,
                              uint16_t position, uint16_t duration,
                              uint8_t track_r, uint8_t track_g, uint8_t track_b,
                              uint8_t fill_r,  uint8_t fill_g,  uint8_t fill_b)
{
    /* Track background. */
    fill_rect(canvas, x0, y0, width, height, track_r, track_g, track_b);
    const int fill_w = host_sim_music_progress_fill_width(position, duration, width);
    if (fill_w < 0) {
        /* Indeterminate: dashed fill. */
        const int dash = 12;
        const int gap  = 8;
        int cursor = 0;
        while (cursor < width) {
            const int len = (cursor + dash <= width) ? dash : (width - cursor);
            fill_rect(canvas, x0 + cursor, y0, len, height, fill_r, fill_g, fill_b);
            cursor += dash + gap;
        }
    } else {
        fill_rect(canvas, x0, y0, fill_w, height, fill_r, fill_g, fill_b);
    }
}

void host_sim_render_music(host_sim_canvas_t      *canvas,
                           const ble_music_data_t *music,
                           uint8_t                 header_flags)
{
    const bool night = (header_flags & BLE_FLAG_NIGHT_MODE) != 0U;
    if (night) {
        host_sim_canvas_fill(canvas, 0, 0, 0);
    } else {
        host_sim_canvas_fill(canvas, 0x0A, 0x1C, 0x3A);
    }

    const uint8_t accent_r = night ? 0xAAU : 0xFFU;
    const uint8_t accent_g = night ? 0x11U : 0xFFU;
    const uint8_t accent_b = night ? 0x11U : 0xFFU;
    const uint8_t dim_r    = night ? 0x66U : 0xBBU;
    const uint8_t dim_g    = night ? 0x00U : 0xBBU;
    const uint8_t dim_b    = night ? 0x00U : 0xBBU;
    const uint8_t faint_r  = night ? 0x33U : 0x88U;
    const uint8_t faint_g  = night ? 0x00U : 0x88U;
    const uint8_t faint_b  = night ? 0x00U : 0x88U;

    const int cx = canvas->width  / 2;

    /* Album art placeholder: 80x80 rounded frame near the top. */
    const int art_size = 80;
    const int art_x    = cx - art_size / 2;
    const int art_y    = 90;
    fill_rect(canvas, art_x, art_y, art_size, art_size,
              night ? 0x22U : 0x1EU,
              night ? 0x00U : 0x36U,
              night ? 0x00U : 0x5AU);
    stroke_rect(canvas, art_x, art_y, art_size, art_size, 3,
                accent_r, accent_g, accent_b);
    draw_music_note(canvas, art_x + art_size / 2, art_y + art_size / 2,
                    art_size - 16, accent_r, accent_g, accent_b);

    /* Title. */
    char title_buf[32];
    host_sim_music_uppercase_ascii(music->title, title_buf, sizeof(title_buf));
    char title_draw[24];
    host_sim_music_truncate_with_ellipsis(title_buf, title_draw, sizeof(title_draw));
    const int title_scale = 4;
    const int title_w = host_sim_measure_text(title_draw, title_scale);
    host_sim_draw_text(canvas, title_draw,
                       cx - title_w / 2,
                       art_y + art_size + 18,
                       title_scale,
                       accent_r, accent_g, accent_b);

    /* Artist. */
    char artist_buf[32];
    host_sim_music_uppercase_ascii(music->artist, artist_buf, sizeof(artist_buf));
    char artist_draw[28];
    host_sim_music_truncate_with_ellipsis(artist_buf, artist_draw, sizeof(artist_draw));
    const int artist_scale = 3;
    const int artist_w = host_sim_measure_text(artist_draw, artist_scale);
    host_sim_draw_text(canvas, artist_draw,
                       cx - artist_w / 2,
                       art_y + art_size + 18 + 8 * title_scale + 10,
                       artist_scale,
                       dim_r, dim_g, dim_b);

    /* Album. */
    char album_buf[32];
    host_sim_music_uppercase_ascii(music->album, album_buf, sizeof(album_buf));
    char album_draw[32];
    host_sim_music_truncate_with_ellipsis(album_buf, album_draw, sizeof(album_draw));
    const int album_scale = 2;
    const int album_w = host_sim_measure_text(album_draw, album_scale);
    host_sim_draw_text(canvas, album_draw,
                       cx - album_w / 2,
                       art_y + art_size + 18 + 8 * title_scale + 10 + 8 * artist_scale + 8,
                       album_scale,
                       faint_r, faint_g, faint_b);

    /* Progress bar. */
    const int bar_width  = 300;
    const int bar_height = 10;
    const int bar_x      = cx - bar_width / 2;
    const int bar_y      = 360;
    draw_progress_bar(canvas,
                      bar_x, bar_y, bar_width, bar_height,
                      music->position_seconds, music->duration_seconds,
                      faint_r, faint_g, faint_b,
                      accent_r, accent_g, accent_b);

    /* Time readouts: position on the left, duration on the right, each
     * directly below the bar ends. */
    char pos_buf[12];
    char dur_buf[12];
    host_sim_music_format_time(music->position_seconds, pos_buf, sizeof(pos_buf));
    host_sim_music_format_time(music->duration_seconds, dur_buf, sizeof(dur_buf));
    const int time_scale = 2;
    const int time_h     = 8 * time_scale;
    host_sim_draw_text(canvas, pos_buf, bar_x, bar_y + bar_height + 8,
                       time_scale, dim_r, dim_g, dim_b);
    const int dur_w = host_sim_measure_text(dur_buf, time_scale);
    host_sim_draw_text(canvas, dur_buf,
                       bar_x + bar_width - dur_w,
                       bar_y + bar_height + 8,
                       time_scale, dim_r, dim_g, dim_b);
    (void)time_h;

    /* Play/pause glyph: top-right corner of the dial. */
    const bool playing = (music->music_flags & BLE_MUSIC_FLAG_PLAYING) != 0U;
    draw_play_pause_icon(canvas, canvas->width - 70, 60, playing,
                         accent_r, accent_g, accent_b);

    host_sim_canvas_apply_round_mask(canvas);
}
