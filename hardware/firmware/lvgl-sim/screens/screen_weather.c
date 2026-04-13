/*
 * screen_weather.c — weather screen with condition icons (matches docs/mockups.html).
 *
 * Layout (from the SVG mockup "Weather"):
 *   - Sun/cloud icon:    LVGL shapes (circles, rounded rects, lines), top
 *   - Hero temperature:  "18°"            SCRAM_FONT_HERO,  white
 *   - Condition text:    "Partly Cloudy"  SCRAM_FONT_LABEL, accent blue
 *   - High/low:          "H: 22°  L: 11°" SCRAM_FONT_SMALL, muted gray
 *   - Location:          "Basel, CH"       SCRAM_FONT_SMALL, accent orange
 *
 * Night mode: red palette.
 *
 * ESP-IDF compatible: pure LVGL + ble_protocol, no SDL dependencies.
 */
#include "screens/screen_weather.h"
#include "theme/scram_colors.h"
#include "theme/scram_fonts.h"
#include "theme/scram_theme.h"

#include <stdio.h>

/* ------------------------------------------------------------------ */
/*  Condition text mapping                                              */
/* ------------------------------------------------------------------ */

static const char *condition_to_text(ble_weather_condition_t cond)
{
    switch (cond) {
    case BLE_WEATHER_CLEAR:
        return "Clear";
    case BLE_WEATHER_CLOUDY:
        return "Cloudy";
    case BLE_WEATHER_RAIN:
        return "Rain";
    case BLE_WEATHER_SNOW:
        return "Snow";
    case BLE_WEATHER_FOG:
        return "Fog";
    case BLE_WEATHER_THUNDERSTORM:
        return "Thunderstorm";
    }
    return "Unknown";
}

/* ------------------------------------------------------------------ */
/*  Weather condition icon builders                                     */
/* ------------------------------------------------------------------ */

/* Helper: create a filled circle (dot/sun/etc). */
static lv_obj_t *make_circle(lv_obj_t *parent, int cx, int cy, int r, lv_color_t col, lv_opa_t opa)
{
    lv_obj_t *obj = lv_obj_create(parent);
    lv_obj_set_size(obj, r * 2, r * 2);
    lv_obj_set_style_radius(obj, r, 0);
    lv_obj_set_style_bg_color(obj, col, 0);
    lv_obj_set_style_bg_opa(obj, opa, 0);
    lv_obj_set_style_border_width(obj, 0, 0);
    lv_obj_clear_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(obj, LV_ALIGN_TOP_LEFT, cx - r, cy - r);
    return obj;
}

/* Helper: create a rounded rectangle. */
static lv_obj_t *make_rounded_rect(lv_obj_t *parent, int x, int y, int w, int h, int radius,
                                   lv_color_t col, lv_opa_t opa)
{
    lv_obj_t *obj = lv_obj_create(parent);
    lv_obj_set_size(obj, w, h);
    lv_obj_set_style_radius(obj, radius, 0);
    lv_obj_set_style_bg_color(obj, col, 0);
    lv_obj_set_style_bg_opa(obj, opa, 0);
    lv_obj_set_style_border_width(obj, 0, 0);
    lv_obj_clear_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(obj, LV_ALIGN_TOP_LEFT, x, y);
    return obj;
}

/* Helper: create a small line segment for rain/lightning. */
static void make_line(lv_obj_t *parent, int x1, int y1, int x2, int y2, lv_color_t col, int width)
{
    static lv_point_precise_t pts_pool[32][2];
    static int pts_idx = 0;
    if (pts_idx >= 32)
        pts_idx = 0;

    pts_pool[pts_idx][0].x = x1;
    pts_pool[pts_idx][0].y = y1;
    pts_pool[pts_idx][1].x = x2;
    pts_pool[pts_idx][1].y = y2;

    lv_obj_t *ln = lv_line_create(parent);
    lv_line_set_points(ln, pts_pool[pts_idx], 2);
    lv_obj_set_style_line_color(ln, col, 0);
    lv_obj_set_style_line_width(ln, width, 0);
    lv_obj_set_style_line_rounded(ln, true, 0);
    lv_obj_set_size(ln, 466, 466);
    lv_obj_set_pos(ln, 0, 0);
    pts_idx++;
}

/* Sun icon: large circle with ray lines radiating outward. */
static void draw_icon_clear(lv_obj_t *parent, int cx, int cy, lv_color_t col_sun)
{
    make_circle(parent, cx, cy, 28, col_sun, LV_OPA_90);

    /* 8 rays around the sun. */
    for (int i = 0; i < 8; i++) {
        double angle = (double)i * 3.14159265 / 4.0;
        int inner = 34;
        int outer = 48;
        int x1 = cx + (int)(inner * __builtin_sin(angle));
        int y1 = cy - (int)(inner * __builtin_cos(angle));
        int x2 = cx + (int)(outer * __builtin_sin(angle));
        int y2 = cy - (int)(outer * __builtin_cos(angle));
        make_line(parent, x1, y1, x2, y2, col_sun, 3);
    }
}

/* Cloud icon: overlapping rounded rects + circles to form cloud body. */
static void draw_icon_cloud(lv_obj_t *parent, int cx, int cy, lv_color_t col_cloud)
{
    /* Main cloud body: rounded rectangle. */
    make_rounded_rect(parent, cx - 50, cy - 5, 100, 40, 20, col_cloud, LV_OPA_80);
    /* Upper bumps: circles. */
    make_circle(parent, cx - 15, cy - 15, 22, col_cloud, LV_OPA_80);
    make_circle(parent, cx + 20, cy - 10, 18, col_cloud, LV_OPA_80);
}

/* Partly cloudy: sun peeking behind a cloud. */
static void draw_icon_partly_cloudy(lv_obj_t *parent, int cx, int cy, lv_color_t col_sun,
                                    lv_color_t col_cloud)
{
    /* Sun behind and to the left. */
    make_circle(parent, cx - 20, cy - 15, 25, col_sun, LV_OPA_90);
    /* Cloud in front. */
    make_rounded_rect(parent, cx - 40, cy, 90, 35, 18, col_cloud, LV_OPA_80);
    make_circle(parent, cx - 5, cy - 10, 20, col_cloud, LV_OPA_80);
    make_circle(parent, cx + 25, cy - 5, 16, col_cloud, LV_OPA_80);
}

/* Rain icon: cloud + rain drop lines. */
static void draw_icon_rain(lv_obj_t *parent, int cx, int cy, lv_color_t col_cloud,
                           lv_color_t col_rain)
{
    draw_icon_cloud(parent, cx, cy - 15, col_cloud);
    /* Rain drop lines below cloud. */
    make_line(parent, cx - 25, cy + 25, cx - 30, cy + 42, col_rain, 3);
    make_line(parent, cx, cy + 25, cx - 5, cy + 42, col_rain, 3);
    make_line(parent, cx + 25, cy + 25, cx + 20, cy + 42, col_rain, 3);
}

/* Snow icon: cloud + snowflake dots. */
static void draw_icon_snow(lv_obj_t *parent, int cx, int cy, lv_color_t col_cloud,
                           lv_color_t col_snow)
{
    draw_icon_cloud(parent, cx, cy - 15, col_cloud);
    /* Snowflake dots. */
    make_circle(parent, cx - 25, cy + 28, 4, col_snow, LV_OPA_COVER);
    make_circle(parent, cx, cy + 35, 4, col_snow, LV_OPA_COVER);
    make_circle(parent, cx + 25, cy + 28, 4, col_snow, LV_OPA_COVER);
    make_circle(parent, cx - 12, cy + 42, 3, col_snow, LV_OPA_COVER);
    make_circle(parent, cx + 12, cy + 42, 3, col_snow, LV_OPA_COVER);
}

/* Fog icon: horizontal lines (stripes). */
static void draw_icon_fog(lv_obj_t *parent, int cx, int cy, lv_color_t col_fog)
{
    for (int i = 0; i < 4; i++) {
        int y = cy - 20 + i * 16;
        int half_w = 40 - i * 4;
        make_line(parent, cx - half_w, y, cx + half_w, y, col_fog, 4);
    }
}

/* Thunderstorm icon: cloud + lightning bolt lines. */
static void draw_icon_thunderstorm(lv_obj_t *parent, int cx, int cy, lv_color_t col_cloud,
                                   lv_color_t col_bolt)
{
    draw_icon_cloud(parent, cx, cy - 15, col_cloud);
    /* Lightning bolt: zigzag lines. */
    make_line(parent, cx - 5, cy + 20, cx + 5, cy + 30, col_bolt, 4);
    make_line(parent, cx + 5, cy + 30, cx - 8, cy + 38, col_bolt, 4);
    make_line(parent, cx - 8, cy + 38, cx + 3, cy + 50, col_bolt, 4);
}

static void draw_condition_icon(lv_obj_t *parent, int cx, int cy, ble_weather_condition_t cond,
                                bool night)
{
    lv_color_t col_sun = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_ORANGE;
    lv_color_t col_cloud = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_BLUE;
    lv_color_t col_snow = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_WHITE;
    lv_color_t col_fog = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_bolt = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_ORANGE;
    lv_color_t col_rain = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_BLUE;

    switch (cond) {
    case BLE_WEATHER_CLEAR:
        draw_icon_clear(parent, cx, cy, col_sun);
        break;
    case BLE_WEATHER_CLOUDY:
        draw_icon_partly_cloudy(parent, cx, cy, col_sun, col_cloud);
        break;
    case BLE_WEATHER_RAIN:
        draw_icon_rain(parent, cx, cy, col_cloud, col_rain);
        break;
    case BLE_WEATHER_SNOW:
        draw_icon_snow(parent, cx, cy, col_cloud, col_snow);
        break;
    case BLE_WEATHER_FOG:
        draw_icon_fog(parent, cx, cy, col_fog);
        break;
    case BLE_WEATHER_THUNDERSTORM:
        draw_icon_thunderstorm(parent, cx, cy, col_cloud, col_bolt);
        break;
    default:
        draw_icon_cloud(parent, cx, cy, col_cloud);
        break;
    }
}

/* ------------------------------------------------------------------ */
/*  Screen layout                                                      */
/* ------------------------------------------------------------------ */

void screen_weather_create(lv_obj_t *parent, const ble_weather_data_t *data, uint8_t flags)
{
    bool night = scram_theme_is_night_mode();

    lv_color_t col_text = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_WHITE;
    lv_color_t col_muted = night ? SCRAM_COLOR_NIGHT_MUTED : SCRAM_COLOR_MUTED;
    lv_color_t col_blue = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_BLUE;
    lv_color_t col_orange = night ? SCRAM_COLOR_NIGHT_TEXT : SCRAM_COLOR_ORANGE;

    (void)flags;

    /* Remove padding/scrollbar from parent screen. */
    lv_obj_set_style_pad_all(parent, 0, 0);
    lv_obj_clear_flag(parent, LV_OBJ_FLAG_SCROLLABLE);

    /* If iOS hasn't sent real weather yet (placeholder seed has empty
     * location), show a "loading" hero instead of a fake 0°. */
    bool loaded = data->location_name[0] != '\0';

    /* --- Condition icon (upper region) --- */
    if (loaded) {
        draw_condition_icon(parent, 233, 130, data->condition, night);
    }

    /* --- Hero temperature --- */
    int16_t temp_whole = data->temperature_celsius_x10 / 10;
    char temp_buf[16];
    if (loaded) {
        snprintf(temp_buf, sizeof(temp_buf), "%d C", (int)temp_whole);
    } else {
        snprintf(temp_buf, sizeof(temp_buf), "%s", "--");
    }

    lv_obj_t *lbl_temp = lv_label_create(parent);
    lv_label_set_text(lbl_temp, temp_buf);
    lv_obj_set_style_text_font(lbl_temp, SCRAM_FONT_HERO, 0);
    lv_obj_set_style_text_color(lbl_temp, col_text, 0);
    lv_obj_set_style_text_align(lbl_temp, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_temp, LV_ALIGN_CENTER, 0, 15);

    /* --- Condition text --- */
    lv_obj_t *lbl_cond = lv_label_create(parent);
    lv_label_set_text(lbl_cond, condition_to_text(data->condition));
    lv_obj_set_style_text_font(lbl_cond, SCRAM_FONT_LABEL, 0);
    lv_obj_set_style_text_color(lbl_cond, col_blue, 0);
    lv_obj_set_style_text_align(lbl_cond, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_cond, LV_ALIGN_CENTER, 0, 60);

    /* --- High / Low temperatures --- */
    int16_t high_whole = data->high_celsius_x10 / 10;
    int16_t low_whole = data->low_celsius_x10 / 10;
    char hilo_buf[32];
    snprintf(hilo_buf, sizeof(hilo_buf), "H: %d C  L: %d C", (int)high_whole, (int)low_whole);

    if (loaded) {
        lv_obj_t *lbl_hilo = lv_label_create(parent);
        lv_label_set_text(lbl_hilo, hilo_buf);
        lv_obj_set_style_text_font(lbl_hilo, SCRAM_FONT_SMALL, 0);
        lv_obj_set_style_text_color(lbl_hilo, col_muted, 0);
        lv_obj_set_style_text_align(lbl_hilo, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_align(lbl_hilo, LV_ALIGN_CENTER, 0, 100);
    }

    /* --- Location --- */
    lv_obj_t *lbl_loc = lv_label_create(parent);
    lv_label_set_text(lbl_loc, loaded ? data->location_name : "Loading...");
    lv_obj_set_style_text_font(lbl_loc, SCRAM_FONT_SMALL, 0);
    lv_obj_set_style_text_color(lbl_loc, col_orange, 0);
    lv_obj_set_style_text_align(lbl_loc, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(lbl_loc, LV_ALIGN_CENTER, 0, 130);
}
