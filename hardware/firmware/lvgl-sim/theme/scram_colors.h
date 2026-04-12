/*
 * scram_colors.h — ScramScreen color palette.
 *
 * Matches the exact values from docs/mockups.html and docs/mockups-extra.html.
 * ESP-IDF compatible: pure LVGL, no SDL dependencies.
 */
#ifndef SCRAM_COLORS_H
#define SCRAM_COLORS_H

#include "lvgl.h"

/* Background */
#define SCRAM_COLOR_BG lv_color_hex(0x0A0A0A)

/* Primary text */
#define SCRAM_COLOR_WHITE lv_color_hex(0xFFFFFF)

/* Muted / secondary text */
#define SCRAM_COLOR_MUTED lv_color_hex(0x999999)

/* Inactive arcs, bars, dividers */
#define SCRAM_COLOR_INACTIVE lv_color_hex(0x222222)

/* Accent: primary — active ride data, progress bars, SOC, accept */
#define SCRAM_COLOR_GREEN lv_color_hex(0xF5A623)

/* Accent: blue — heading, time-related, info, weather */
#define SCRAM_COLOR_BLUE lv_color_hex(0x5BACF5)

/* Accent: orange — warnings, elevation, fuel */
#define SCRAM_COLOR_ORANGE lv_color_hex(0xF5A623)

/* Alert: red — radar, alerts, reject, north marker */
#define SCRAM_COLOR_RED lv_color_hex(0xE24B4A)

/* Secondary: purple — calendar events */
#define SCRAM_COLOR_PURPLE lv_color_hex(0xC084FC)

/* Night mode palette (red-on-black) */
#define SCRAM_COLOR_NIGHT_TEXT  lv_color_hex(0xCC3333)
#define SCRAM_COLOR_NIGHT_MUTED lv_color_hex(0x661111)
#define SCRAM_COLOR_NIGHT_BG    lv_color_hex(0x050000)

#endif /* SCRAM_COLORS_H */
