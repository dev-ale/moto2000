/*
 * screen_compass.c — compass screen with rotating dial (matches docs/mockups.html).
 *
 * Layout (from the SVG mockup "Compass"):
 *   - Outer ring:     subtle circle stroke #222, radius ~75% of display
 *   - Cardinal labels: N (red #e24b4a, top, bold), E/S/W (#999, at 90 intervals)
 *   - Tick marks:     12 marks at 30-degree intervals (major at N/E/S/W), rotated
 *   - Needle:         classic diamond — red north half, dark gray south half
 *   - Digital readout: "042" centered, white, small-medium font
 *   - MAG/TRU label:  small indicator below the readout
 *
 * The dial rotates so that the current heading faces up. Cardinal labels and
 * ticks are positioned around the ring at angles offset by the heading.
 *
 * Night mode: labels become dim red, ring becomes dark red, needle stays red.
 *
 * Implementation: Option C — lv_line arrays for ticks/needle, lv_label for
 * cardinals, all positions computed via trig. No canvas or image rotation
 * needed, and works with the existing lv_conf.h widget set.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_compass.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <math.h>
#include <stdio.h>

/* ------------------------------------------------------------------ */
/*  Constants                                                          */
/* ------------------------------------------------------------------ */

#define DISPLAY_SIZE       466
#define CENTER             (DISPLAY_SIZE / 2)
#define OUTER_RADIUS       175 /* ~75% of half-display (233 * 0.75) */
#define TICK_OUTER_RADIUS  (OUTER_RADIUS - 2)
#define TICK_MAJOR_LEN     18
#define TICK_MINOR_LEN     10
#define LABEL_RADIUS       (OUTER_RADIUS - 35)
#define NEEDLE_TIP_RADIUS  95 /* distance from center to needle tip */
#define NEEDLE_TAIL_RADIUS 95 /* distance from center to needle tail */
#define NEEDLE_HALF_WIDTH  15 /* half-width at the center */

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ------------------------------------------------------------------ */
/*  Trig helpers                                                       */
/* ------------------------------------------------------------------ */

/* Convert a compass bearing (degrees x10, 0 = north, CW) relative to
 * the current heading into screen coordinates on a circle of given radius. */
static void dial_point(uint16_t heading_x10, uint16_t bearing_x10, int radius, int *out_x,
                       int *out_y)
{
    int32_t rel = (int32_t)bearing_x10 - (int32_t)heading_x10;
    /* Normalize to 0..3599 */
    rel = rel % 3600;
    if (rel < 0)
        rel += 3600;

    double theta = (double)rel / 10.0 * (M_PI / 180.0);
    *out_x = CENTER + (int)lround(sin(theta) * (double)radius);
    *out_y = CENTER - (int)lround(cos(theta) * (double)radius);
}

/* Get the displayed heading (magnetic or true). */
static uint16_t displayed_heading_x10(const ble_compass_data_t *data)
{
    bool want_true = (data->compass_flags & BLE_COMPASS_FLAG_USE_TRUE_HEADING) != 0;
    if (want_true && data->true_heading_deg_x10 != BLE_COMPASS_TRUE_HEADING_UNKNOWN) {
        return data->true_heading_deg_x10;
    }
    return data->magnetic_heading_deg_x10;
}

/* Round heading_x10 to whole degrees, wrapping 360 -> 0. */
static uint16_t heading_whole_deg(uint16_t heading_x10)
{
    uint32_t rounded = ((uint32_t)heading_x10 + 5U) / 10U;
    return (uint16_t)(rounded % 360U);
}

/* ------------------------------------------------------------------ */
/*  Outer ring                                                         */
/* ------------------------------------------------------------------ */

static void create_outer_ring(lv_obj_t *parent, lv_color_t col)
{
    lv_obj_t *ring = lv_obj_create(parent);
    lv_obj_set_size(ring, OUTER_RADIUS * 2, OUTER_RADIUS * 2);
    lv_obj_align(ring, LV_ALIGN_CENTER, 0, 0);
    lv_obj_set_style_radius(ring, OUTER_RADIUS, 0);
    lv_obj_set_style_bg_opa(ring, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_color(ring, col, 0);
    lv_obj_set_style_border_width(ring, 2, 0);
    lv_obj_set_style_border_opa(ring, LV_OPA_COVER, 0);
    lv_obj_clear_flag(ring, LV_OBJ_FLAG_SCROLLABLE);
}

/* ------------------------------------------------------------------ */
/*  Tick marks                                                         */
/* ------------------------------------------------------------------ */

/* Each tick is a short lv_line from inner to outer radius. */
static void create_ticks(lv_obj_t *parent, uint16_t heading_x10, lv_color_t col_major,
                         lv_color_t col_minor)
{
    /* 12 ticks at 30-degree intervals. */
    for (int deg = 0; deg < 360; deg += 30) {
        bool major = (deg % 90) == 0;
        int tick_len = major ? TICK_MAJOR_LEN : TICK_MINOR_LEN;
        int inner_r = TICK_OUTER_RADIUS - tick_len;
        uint16_t bearing_x10 = (uint16_t)(deg * 10);

        int ox, oy, ix, iy;
        dial_point(heading_x10, bearing_x10, TICK_OUTER_RADIUS, &ox, &oy);
        dial_point(heading_x10, bearing_x10, inner_r, &ix, &iy);

        lv_obj_t *line = lv_line_create(parent);
        static lv_point_precise_t pts[12][2]; /* static storage for each tick */
        /* Use the loop index to pick storage. */
        int idx = deg / 30;
        pts[idx][0].x = ix;
        pts[idx][0].y = iy;
        pts[idx][1].x = ox;
        pts[idx][1].y = oy;
        lv_line_set_points(line, pts[idx], 2);

        lv_obj_set_style_line_color(line, major ? col_major : col_minor, 0);
        lv_obj_set_style_line_width(line, major ? 3 : 2, 0);

        /* Lines use the parent's coordinate system with absolute coords. */
        lv_obj_set_size(line, DISPLAY_SIZE, DISPLAY_SIZE);
        lv_obj_set_pos(line, 0, 0);
    }
}

/* ------------------------------------------------------------------ */
/*  Cardinal labels                                                    */
/* ------------------------------------------------------------------ */

static void create_cardinal_labels(lv_obj_t *parent, uint16_t heading_x10, lv_color_t col_north,
                                   lv_color_t col_other)
{
    static const char *labels[] = { "N", "E", "S", "W" };
    static const int bearings[] = { 0, 90, 180, 270 };

    for (int i = 0; i < 4; i++) {
        int px, py;
        dial_point(heading_x10, (uint16_t)(bearings[i] * 10), LABEL_RADIUS, &px, &py);

        lv_obj_t *lbl = lv_label_create(parent);
        lv_label_set_text(lbl, labels[i]);

        bool is_north = (i == 0);
        lv_obj_set_style_text_font(lbl, is_north ? SCRAM_FONT_VALUE : SCRAM_FONT_LABEL, 0);
        lv_obj_set_style_text_color(lbl, is_north ? col_north : col_other, 0);
        lv_obj_set_style_text_align(lbl, LV_TEXT_ALIGN_CENTER, 0);

        /* Position label centered on the computed point. */
        lv_obj_align(lbl, LV_ALIGN_TOP_LEFT, 0, 0);
        lv_obj_update_layout(lbl);
        int lw = lv_obj_get_width(lbl);
        int lh = lv_obj_get_height(lbl);
        lv_obj_set_pos(lbl, px - lw / 2, py - lh / 2);
    }
}

/* ------------------------------------------------------------------ */
/*  Compass needle (diamond shape)                                     */
/* ------------------------------------------------------------------ */

/* The needle is a classic diamond: the north tip points toward magnetic
 * north on the dial, and the south tip points opposite. Since the dial
 * rotates to put the current heading at top, the needle's north tip
 * always points at the bearing 0 (north) position on the dial.
 *
 * We draw the needle as two triangles (north half = red, south half = gray)
 * using lv_line to outline the diamond shape filled with colored objects. */
static void create_needle(lv_obj_t *parent, uint16_t heading_x10, lv_color_t col_north,
                          lv_color_t col_south)
{
    /* Needle points: tip_n (north tip), tip_s (south tip),
     * left and right at center. */
    int nx, ny; /* North tip */
    int sx, sy; /* South tip */
    int lx, ly; /* Left wing */
    int rx, ry; /* Right wing */

    dial_point(heading_x10, 0, NEEDLE_TIP_RADIUS, &nx, &ny);
    dial_point(heading_x10, 1800, NEEDLE_TAIL_RADIUS, &sx, &sy);
    dial_point(heading_x10, 2700, NEEDLE_HALF_WIDTH, &lx, &ly);
    dial_point(heading_x10, 900, NEEDLE_HALF_WIDTH, &rx, &ry);

    /* North half: triangle from north-tip to left-wing to right-wing.
     * We draw as a filled polygon via two overlapping line sets. Since
     * LVGL doesn't have polygon fill, we use two thick-line triangles
     * drawn as 3-point line paths to create the visual shape.
     *
     * Better approach: draw with multiple thin lines to simulate fill. */

    /* North triangle (tip -> right -> center -> left -> tip) */
    {
        static lv_point_precise_t pts_n[4];
        pts_n[0].x = nx;
        pts_n[0].y = ny;
        pts_n[1].x = rx;
        pts_n[1].y = ry;
        pts_n[2].x = lx;
        pts_n[2].y = ly;
        pts_n[3].x = nx;
        pts_n[3].y = ny;

        /* Fill north triangle by drawing many lines from the tip to the base */
        int steps = 20;
        for (int i = 0; i <= steps; i++) {
            static lv_point_precise_t fill_pts[21][2];
            double t = (double)i / (double)steps;
            int bx = (int)lround((double)lx + t * ((double)rx - (double)lx));
            int by = (int)lround((double)ly + t * ((double)ry - (double)ly));

            fill_pts[i][0].x = nx;
            fill_pts[i][0].y = ny;
            fill_pts[i][1].x = bx;
            fill_pts[i][1].y = by;

            lv_obj_t *ln = lv_line_create(parent);
            lv_line_set_points(ln, fill_pts[i], 2);
            lv_obj_set_style_line_color(ln, col_north, 0);
            lv_obj_set_style_line_width(ln, 3, 0);
            lv_obj_set_size(ln, DISPLAY_SIZE, DISPLAY_SIZE);
            lv_obj_set_pos(ln, 0, 0);
        }
    }

    /* South triangle (tail -> right -> center -> left -> tail) */
    {
        int steps = 20;
        for (int i = 0; i <= steps; i++) {
            static lv_point_precise_t fill_pts_s[21][2];
            double t = (double)i / (double)steps;
            int bx = (int)lround((double)lx + t * ((double)rx - (double)lx));
            int by = (int)lround((double)ly + t * ((double)ry - (double)ly));

            fill_pts_s[i][0].x = sx;
            fill_pts_s[i][0].y = sy;
            fill_pts_s[i][1].x = bx;
            fill_pts_s[i][1].y = by;

            lv_obj_t *ln = lv_line_create(parent);
            lv_line_set_points(ln, fill_pts_s[i], 2);
            lv_obj_set_style_line_color(ln, col_south, 0);
            lv_obj_set_style_line_width(ln, 3, 0);
            lv_obj_set_size(ln, DISPLAY_SIZE, DISPLAY_SIZE);
            lv_obj_set_pos(ln, 0, 0);
        }
    }
}

/* ------------------------------------------------------------------ */
/*  Screen layout                                                      */
/* ------------------------------------------------------------------ */

void screen_compass_create(lv_obj_t *parent, const ble_compass_data_t *data, uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_WHITE;
    lv_color_t col_muted = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_ring = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_INACTIVE;
    lv_color_t col_north = night ? SCRAM_COLOR_RED : SCRAM_COLOR_RED;
    lv_color_t col_needle_s = night ? lv_color_hex(0x333333) : lv_color_hex(0x444444);
    lv_color_t col_tick_major = night ? SCRAM_COLOR_NIGHT_MUTED : lv_color_hex(0x333333);
    lv_color_t col_tick_minor = night ? lv_color_hex(0x330808) : lv_color_hex(0x222222);

    (void)flags;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    uint16_t heading_x10 = displayed_heading_x10(data);
    uint16_t deg = heading_whole_deg(heading_x10);

    /* --- Outer ring --- */
    create_outer_ring(parent, col_ring);

    /* --- Tick marks --- */
    create_ticks(parent, heading_x10, col_tick_major, col_tick_minor);

    /* --- Cardinal labels --- */
    create_cardinal_labels(parent, heading_x10, col_north, col_muted);

    /* --- Compass needle --- */
    create_needle(parent, heading_x10, col_north, col_needle_s);

    /* Digital heading readout removed: noisy and redundant when the
     * needle and cardinal labels already convey the bearing. */
    (void)deg;

    /* --- MAG / TRU indicator --- */
    bool use_true = (data->compass_flags & BLE_COMPASS_FLAG_USE_TRUE_HEADING) != 0;
    bool true_known = data->true_heading_deg_x10 != BLE_COMPASS_TRUE_HEADING_UNKNOWN;
    const char *mag_tru = (use_true && true_known) ? "TRU" : "MAG";

    lv_obj_t *lbl_mode = lv_label_create(parent);
    lv_label_set_text(lbl_mode, mag_tru);
    lv_obj_set_style_text_font(lbl_mode, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_mode, col_muted, 0);
    lv_obj_set_style_text_align(lbl_mode, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_mode, LV_ALIGN_CENTER, 0, -10);
}
