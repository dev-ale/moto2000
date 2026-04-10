/*
 * screen_navigation.c -- LVGL navigation screen with turn arrows.
 *
 * Layout (from the SVG mockup "Navigation"):
 *   - Background:   #0a0a0a (SCRAM_COLOR_BG)
 *   - Turn arrow:   large green (#4dd88a) polygon, upper ~40% of screen
 *   - Street name:  muted gray (#999), SCRAM_FONT_SMALL, centered
 *   - Distance:     large white hero text (e.g. "340m" or "1.2km")
 *   - Maneuver:     accent green, SCRAM_FONT_SMALL, centered
 *   - ETA line:     muted gray, SCRAM_FONT_SMALL, bottom
 *
 * Arrow rendering: each maneuver type maps to a coarse arrow shape
 * (straight, left, right, u-turn, roundabout, arrive, fork). Arrows
 * are drawn as filled triangles using lv_line fan fills -- the same
 * technique used in screen_compass.c for the needle diamond. This
 * avoids needing lv_canvas or image assets while keeping glyphs big
 * and instantly recognizable.
 *
 * Night mode: green arrows become red; text follows theme palette.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_navigation.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/*  Constants                                                          */
/* ------------------------------------------------------------------ */

#define DISPLAY_SIZE 466
#define CENTER       (DISPLAY_SIZE / 2)

/* Arrow region: centered horizontally, upper portion of screen. */
#define ARROW_CX   CENTER
#define ARROW_CY   130 /* center of arrow drawing region */
#define ARROW_SIZE 90  /* half-extent of arrow shapes */

/* ------------------------------------------------------------------ */
/*  Maneuver type to arrow shape and label                             */
/* ------------------------------------------------------------------ */

typedef enum {
    NAV_ARROW_STRAIGHT = 0,
    NAV_ARROW_LEFT,
    NAV_ARROW_RIGHT,
    NAV_ARROW_SLIGHT_LEFT,
    NAV_ARROW_SLIGHT_RIGHT,
    NAV_ARROW_SHARP_LEFT,
    NAV_ARROW_SHARP_RIGHT,
    NAV_ARROW_U_TURN_LEFT,
    NAV_ARROW_U_TURN_RIGHT,
    NAV_ARROW_ROUNDABOUT,
    NAV_ARROW_ARRIVE,
    NAV_ARROW_FORK_LEFT,
    NAV_ARROW_FORK_RIGHT,
    NAV_ARROW_MERGE,
    NAV_ARROW_NONE,
} nav_arrow_t;

static nav_arrow_t maneuver_to_arrow(ble_maneuver_t m)
{
    switch (m) {
    case BLE_MANEUVER_STRAIGHT:
        return NAV_ARROW_STRAIGHT;
    case BLE_MANEUVER_SLIGHT_LEFT:
        return NAV_ARROW_SLIGHT_LEFT;
    case BLE_MANEUVER_LEFT:
        return NAV_ARROW_LEFT;
    case BLE_MANEUVER_SHARP_LEFT:
        return NAV_ARROW_SHARP_LEFT;
    case BLE_MANEUVER_U_TURN_LEFT:
        return NAV_ARROW_U_TURN_LEFT;
    case BLE_MANEUVER_SLIGHT_RIGHT:
        return NAV_ARROW_SLIGHT_RIGHT;
    case BLE_MANEUVER_RIGHT:
        return NAV_ARROW_RIGHT;
    case BLE_MANEUVER_SHARP_RIGHT:
        return NAV_ARROW_SHARP_RIGHT;
    case BLE_MANEUVER_U_TURN_RIGHT:
        return NAV_ARROW_U_TURN_RIGHT;
    case BLE_MANEUVER_ROUNDABOUT_ENTER:
        return NAV_ARROW_ROUNDABOUT;
    case BLE_MANEUVER_ROUNDABOUT_EXIT:
        return NAV_ARROW_ROUNDABOUT;
    case BLE_MANEUVER_MERGE:
        return NAV_ARROW_MERGE;
    case BLE_MANEUVER_FORK_LEFT:
        return NAV_ARROW_FORK_LEFT;
    case BLE_MANEUVER_FORK_RIGHT:
        return NAV_ARROW_FORK_RIGHT;
    case BLE_MANEUVER_ARRIVE:
        return NAV_ARROW_ARRIVE;
    case BLE_MANEUVER_NONE:
        return NAV_ARROW_NONE;
    }
    return NAV_ARROW_STRAIGHT;
}

static const char *maneuver_to_text(ble_maneuver_t m)
{
    switch (m) {
    case BLE_MANEUVER_STRAIGHT:
        return "Continue straight";
    case BLE_MANEUVER_SLIGHT_LEFT:
        return "Slight left";
    case BLE_MANEUVER_LEFT:
        return "Turn left";
    case BLE_MANEUVER_SHARP_LEFT:
        return "Sharp left";
    case BLE_MANEUVER_U_TURN_LEFT:
        return "U-turn left";
    case BLE_MANEUVER_SLIGHT_RIGHT:
        return "Slight right";
    case BLE_MANEUVER_RIGHT:
        return "Turn right";
    case BLE_MANEUVER_SHARP_RIGHT:
        return "Sharp right";
    case BLE_MANEUVER_U_TURN_RIGHT:
        return "U-turn right";
    case BLE_MANEUVER_ROUNDABOUT_ENTER:
        return "Enter roundabout";
    case BLE_MANEUVER_ROUNDABOUT_EXIT:
        return "Exit roundabout";
    case BLE_MANEUVER_MERGE:
        return "Merge";
    case BLE_MANEUVER_FORK_LEFT:
        return "Fork left";
    case BLE_MANEUVER_FORK_RIGHT:
        return "Fork right";
    case BLE_MANEUVER_ARRIVE:
        return "Arrive";
    case BLE_MANEUVER_NONE:
        return "";
    }
    return "";
}

/* ------------------------------------------------------------------ */
/*  Arrow drawing helpers (lv_line fan-fill triangles)                  */
/* ------------------------------------------------------------------ */

/*
 * Draw a filled triangle on `parent` using fan-fill lines (same
 * technique as screen_compass.c needle). We draw `steps` lines from
 * vertex (ax,ay) to interpolated points along the edge (bx,by)-(cx,cy).
 */

/* Maximum number of fill steps per triangle. */
#define FILL_STEPS 12

/* Static storage for line points. We need enough slots for all triangles
 * drawn during a single screen build. Each arrow uses at most 6 triangles
 * x FILL_STEPS lines x 2 points. We use a pool and bump-allocate. */
#define MAX_LINE_PAIRS 512
static lv_point_precise_t s_pts[MAX_LINE_PAIRS][2];
static int s_pts_idx;

static void fill_triangle(lv_obj_t *parent, lv_color_t col, int ax, int ay, int bx, int by, int cx,
                          int cy)
{
    for (int i = 0; i <= FILL_STEPS; i++) {
        if (s_pts_idx >= MAX_LINE_PAIRS)
            return;
        double t = (double)i / (double)FILL_STEPS;
        int ex = (int)lround((double)bx + t * ((double)cx - (double)bx));
        int ey = (int)lround((double)by + t * ((double)cy - (double)by));

        s_pts[s_pts_idx][0].x = ax;
        s_pts[s_pts_idx][0].y = ay;
        s_pts[s_pts_idx][1].x = ex;
        s_pts[s_pts_idx][1].y = ey;

        lv_obj_t *ln = lv_line_create(parent);
        lv_line_set_points(ln, s_pts[s_pts_idx], 2);
        lv_obj_set_style_line_color(ln, col, 0);
        lv_obj_set_style_line_width(ln, 3, 0);
        lv_obj_set_size(ln, DISPLAY_SIZE, DISPLAY_SIZE);
        lv_obj_set_pos(ln, 0, 0);
        s_pts_idx++;
    }
}

/* Draw a filled rectangle using two triangles. */
static void fill_rect_tri(lv_obj_t *parent, lv_color_t col, int x, int y, int w, int h)
{
    fill_triangle(parent, col, x, y, x + w, y, x, y + h);
    fill_triangle(parent, col, x + w, y, x + w, y + h, x, y + h);
}

/* Draw a filled circle approximation (using triangle fan from center). */
static void fill_circle(lv_obj_t *parent, lv_color_t col, int cx, int cy, int radius)
{
    int segments = 10;
    for (int i = 0; i < segments; i++) {
        double a0 = 2.0 * M_PI * (double)i / (double)segments;
        double a1 = 2.0 * M_PI * (double)(i + 1) / (double)segments;
        int x0 = cx + (int)lround(cos(a0) * (double)radius);
        int y0 = cy + (int)lround(sin(a0) * (double)radius);
        int x1 = cx + (int)lround(cos(a1) * (double)radius);
        int y1 = cy + (int)lround(sin(a1) * (double)radius);
        fill_triangle(parent, col, cx, cy, x0, y0, x1, y1);
    }
}

/* ------------------------------------------------------------------ */
/*  Individual arrow shape renderers                                   */
/* ------------------------------------------------------------------ */

/* Straight arrow: up-pointing triangle head + vertical shaft. */
static void draw_arrow_straight(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    /* Triangular head: tip at top, wide base. */
    fill_triangle(parent, col, cx, cy - 70, /* tip */
                  cx - 50, cy - 10,         /* left base */
                  cx + 50, cy - 10);        /* right base */
    /* Shaft: vertical rectangle below head. */
    fill_rect_tri(parent, col, cx - 16, cy - 15, 32, 60);
}

/* Left arrow: left-pointing triangle head + horizontal shaft. */
static void draw_arrow_left(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    /* Triangular head pointing left. */
    fill_triangle(parent, col, cx - 70, cy, /* tip */
                  cx - 10, cy - 50,         /* top base */
                  cx - 10, cy + 50);        /* bottom base */
    /* Horizontal shaft to the right. */
    fill_rect_tri(parent, col, cx - 15, cy - 16, 60, 32);
}

/* Right arrow: mirror of left. */
static void draw_arrow_right(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    fill_triangle(parent, col, cx + 70, cy, cx + 10, cy - 50, cx + 10, cy + 50);
    fill_rect_tri(parent, col, cx - 45, cy - 16, 60, 32);
}

/* Slight left: diagonal arrow pointing upper-left. */
static void draw_arrow_slight_left(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    /* Diagonal head pointing upper-left. */
    fill_triangle(parent, col, cx - 50, cy - 55, /* tip */
                  cx + 5, cy - 40,               /* right */
                  cx - 35, cy + 10);             /* bottom */
    /* Shaft going lower-right. */
    fill_rect_tri(parent, col, cx - 20, cy - 15, 28, 55);
}

/* Slight right: mirror. */
static void draw_arrow_slight_right(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    fill_triangle(parent, col, cx + 50, cy - 55, cx - 5, cy - 40, cx + 35, cy + 10);
    fill_rect_tri(parent, col, cx - 8, cy - 15, 28, 55);
}

/* Sharp left: diagonal arrow pointing lower-left. */
static void draw_arrow_sharp_left(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    fill_triangle(parent, col, cx - 60, cy + 30, /* tip */
                  cx - 5, cy + 20,               /* right */
                  cx - 45, cy - 30);             /* top */
    /* Shaft going up. */
    fill_rect_tri(parent, col, cx - 16, cy - 40, 32, 55);
}

/* Sharp right: mirror. */
static void draw_arrow_sharp_right(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    fill_triangle(parent, col, cx + 60, cy + 30, cx + 5, cy + 20, cx + 45, cy - 30);
    fill_rect_tri(parent, col, cx - 16, cy - 40, 32, 55);
}

/* U-turn left: curved shape approximated with shaft + crossbar + head. */
static void draw_arrow_u_turn_left(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    /* Right shaft going up. */
    fill_rect_tri(parent, col, cx + 15, cy - 40, 20, 70);
    /* Horizontal bar across top. */
    fill_rect_tri(parent, col, cx - 25, cy - 50, 60, 18);
    /* Left shaft going down. */
    fill_rect_tri(parent, col, cx - 25, cy - 35, 20, 60);
    /* Downward-pointing head at left shaft bottom. */
    fill_triangle(parent, col, cx - 15, cy + 40, /* tip */
                  cx - 45, cy + 5,               /* left */
                  cx + 15, cy + 5);              /* right */
}

/* U-turn right: mirror. */
static void draw_arrow_u_turn_right(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    fill_rect_tri(parent, col, cx - 35, cy - 40, 20, 70);
    fill_rect_tri(parent, col, cx - 35, cy - 50, 60, 18);
    fill_rect_tri(parent, col, cx + 5, cy - 35, 20, 60);
    fill_triangle(parent, col, cx + 15, cy + 40, cx - 15, cy + 5, cx + 45, cy + 5);
}

/* Roundabout: circle ring + exit arrow. */
static void draw_arrow_roundabout(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    /* Outer circle. */
    fill_circle(parent, col, cx, cy + 5, 40);
    /* Inner circle (background color to make ring). */
    fill_circle(parent, SCRAM_COLOR_BG, cx, cy + 5, 25);
    /* Exit arrow pointing up-right from the ring. */
    fill_triangle(parent, col, cx + 20, cy - 55, /* tip */
                  cx - 5, cy - 30,               /* left */
                  cx + 30, cy - 20);             /* right */
    fill_rect_tri(parent, col, cx - 2, cy - 35, 14, 20);
}

/* Arrive: destination marker (filled circle with inner dot). */
static void draw_arrow_arrive(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    fill_circle(parent, col, cx, cy, 45);
    fill_circle(parent, SCRAM_COLOR_BG, cx, cy, 30);
    fill_circle(parent, col, cx, cy, 16);
}

/* Fork left: vertical shaft with angled branch to left. */
static void draw_arrow_fork_left(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    /* Main shaft. */
    fill_rect_tri(parent, col, cx - 12, cy - 20, 24, 65);
    /* Upward head. */
    fill_triangle(parent, col, cx, cy - 55, cx - 35, cy - 15, cx + 35, cy - 15);
    /* Branch going upper-left. */
    fill_triangle(parent, col, cx - 55, cy - 40, /* tip */
                  cx - 15, cy - 10,              /* right */
                  cx - 15, cy - 35);             /* top-right */
}

/* Fork right: mirror. */
static void draw_arrow_fork_right(lv_obj_t *parent, lv_color_t col)
{
    int cx = ARROW_CX;
    int cy = ARROW_CY;
    fill_rect_tri(parent, col, cx - 12, cy - 20, 24, 65);
    fill_triangle(parent, col, cx, cy - 55, cx - 35, cy - 15, cx + 35, cy - 15);
    fill_triangle(parent, col, cx + 55, cy - 40, cx + 15, cy - 10, cx + 15, cy - 35);
}

/* Merge: same as straight (merge onto the road ahead). */
static void draw_arrow_merge(lv_obj_t *parent, lv_color_t col)
{
    draw_arrow_straight(parent, col);
}

static void draw_arrow(lv_obj_t *parent, nav_arrow_t shape, lv_color_t col)
{
    switch (shape) {
    case NAV_ARROW_STRAIGHT:
        draw_arrow_straight(parent, col);
        return;
    case NAV_ARROW_LEFT:
        draw_arrow_left(parent, col);
        return;
    case NAV_ARROW_RIGHT:
        draw_arrow_right(parent, col);
        return;
    case NAV_ARROW_SLIGHT_LEFT:
        draw_arrow_slight_left(parent, col);
        return;
    case NAV_ARROW_SLIGHT_RIGHT:
        draw_arrow_slight_right(parent, col);
        return;
    case NAV_ARROW_SHARP_LEFT:
        draw_arrow_sharp_left(parent, col);
        return;
    case NAV_ARROW_SHARP_RIGHT:
        draw_arrow_sharp_right(parent, col);
        return;
    case NAV_ARROW_U_TURN_LEFT:
        draw_arrow_u_turn_left(parent, col);
        return;
    case NAV_ARROW_U_TURN_RIGHT:
        draw_arrow_u_turn_right(parent, col);
        return;
    case NAV_ARROW_ROUNDABOUT:
        draw_arrow_roundabout(parent, col);
        return;
    case NAV_ARROW_ARRIVE:
        draw_arrow_arrive(parent, col);
        return;
    case NAV_ARROW_FORK_LEFT:
        draw_arrow_fork_left(parent, col);
        return;
    case NAV_ARROW_FORK_RIGHT:
        draw_arrow_fork_right(parent, col);
        return;
    case NAV_ARROW_MERGE:
        draw_arrow_merge(parent, col);
        return;
    case NAV_ARROW_NONE:
        return; /* no arrow */
    }
}

/* ------------------------------------------------------------------ */
/*  Distance formatting                                                */
/* ------------------------------------------------------------------ */

static void format_distance(uint16_t meters, char *buf, size_t buf_len)
{
    if (meters == 0xFFFFU) {
        snprintf(buf, buf_len, "--");
        return;
    }
    if (meters < 1000U) {
        snprintf(buf, buf_len, "%um", (unsigned)meters);
    } else {
        unsigned tenths = (unsigned)(meters / 100U);
        unsigned whole = tenths / 10U;
        unsigned frac = tenths % 10U;
        if (whole >= 100U) {
            snprintf(buf, buf_len, "%ukm", whole);
        } else {
            snprintf(buf, buf_len, "%u.%ukm", whole, frac);
        }
    }
}

/* ------------------------------------------------------------------ */
/*  ETA line formatting                                                */
/* ------------------------------------------------------------------ */

static void format_eta_line(uint16_t eta_minutes, uint16_t remaining_km_x10, char *buf,
                            size_t buf_len)
{
    char eta_part[16];
    char rem_part[16];

    if (eta_minutes == 0xFFFFU) {
        snprintf(eta_part, sizeof(eta_part), "ETA --");
    } else {
        /* Format as HH:MM if >= 60 minutes, otherwise Xm. */
        if (eta_minutes >= 60U) {
            unsigned h = (unsigned)(eta_minutes / 60U);
            unsigned m = (unsigned)(eta_minutes % 60U);
            snprintf(eta_part, sizeof(eta_part), "ETA %u:%02u", h, m);
        } else {
            snprintf(eta_part, sizeof(eta_part), "ETA %um", (unsigned)eta_minutes);
        }
    }

    if (remaining_km_x10 == 0xFFFFU) {
        snprintf(rem_part, sizeof(rem_part), "-- km");
    } else {
        unsigned whole = (unsigned)(remaining_km_x10 / 10U);
        unsigned frac = (unsigned)(remaining_km_x10 % 10U);
        if (whole >= 100U) {
            snprintf(rem_part, sizeof(rem_part), "%u km", whole);
        } else {
            snprintf(rem_part, sizeof(rem_part), "%u.%u km", whole, frac);
        }
    }

    snprintf(buf, buf_len, "%s  \xE2\x80\x94  %s", eta_part, rem_part);
}

/* ------------------------------------------------------------------ */
/*  Public entry point                                                 */
/* ------------------------------------------------------------------ */

void screen_navigation_create(lv_obj_t *parent, const ble_nav_data_t *nav, uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_WHITE;
    lv_color_t col_muted = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_accent = night ? SCRAM_COLOR_RED : SCRAM_COLOR_GREEN;

    (void)flags;

    /* Reset static line-point pool. */
    s_pts_idx = 0;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* --- Hero turn arrow --- */
    nav_arrow_t shape = maneuver_to_arrow(nav->maneuver);
    draw_arrow(parent, shape, col_accent);

    /* --- Street name (muted, small, centered above distance) --- */
    lv_obj_t *lbl_street = lv_label_create(parent);
    lv_label_set_text(lbl_street, nav->street_name);
    lv_obj_set_style_text_font(lbl_street, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_street, col_muted, 0);
    lv_obj_set_style_text_align(lbl_street, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_width(lbl_street, 350);
    lv_label_set_long_mode(lbl_street, LV_LABEL_LONG_DOT);
    lv_obj_align(lbl_street, LV_ALIGN_CENTER, 0, 25);

    /* --- Distance to next maneuver (hero-sized, white, centered) --- */
    char dist_buf[16];
    format_distance(nav->distance_to_maneuver_m, dist_buf, sizeof(dist_buf));

    lv_obj_t *lbl_dist = lv_label_create(parent);
    lv_label_set_text(lbl_dist, dist_buf);
    lv_obj_set_style_text_font(lbl_dist, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_dist, col_text, 0);
    lv_obj_set_style_text_align(lbl_dist, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_dist, LV_ALIGN_CENTER, 0, 65);

    /* --- Maneuver description text (accent green, small) --- */
    const char *maneuver_text = maneuver_to_text(nav->maneuver);
    if (maneuver_text[0] != '\0') {
        lv_obj_t *lbl_maneuver = lv_label_create(parent);
        lv_label_set_text(lbl_maneuver, maneuver_text);
        lv_obj_set_style_text_font(lbl_maneuver, SCRAM_FONT_SMALL, 0);
        lv_obj_set_style_text_color(lbl_maneuver, col_accent, 0);
        lv_obj_set_style_text_align(lbl_maneuver, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_align(lbl_maneuver, LV_ALIGN_CENTER, 0, 110);
    }

    /* --- ETA + remaining distance (muted, smallest, bottom) --- */
    char eta_buf[48];
    format_eta_line(nav->eta_minutes, nav->remaining_km_x10, eta_buf, sizeof(eta_buf));

    lv_obj_t *lbl_eta = lv_label_create(parent);
    lv_label_set_text(lbl_eta, eta_buf);
    lv_obj_set_style_text_font(lbl_eta, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_eta, col_muted, 0);
    lv_obj_set_style_text_align(lbl_eta, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_eta, LV_ALIGN_CENTER, 0, 145);
}
