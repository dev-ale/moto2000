/*
 * scram_fonts.h — font size aliases for ScramScreen.
 *
 * Currently mapped to LVGL's built-in Montserrat fonts. Replace with
 * custom Inter fonts generated via lv_font_conv (see fonts/README.md).
 *
 * Typography hierarchy (from docs/mockups.html):
 *   Hero digits (speed, time, distance):  ~42-48pt, white, medium weight
 *   Secondary values (heading, temp):     ~18-24pt, accent color
 *   Labels / units:                       ~14-16pt, muted gray
 *   Small metadata:                       ~10-12pt, muted gray
 *
 * ESP-IDF compatible: pure LVGL, no SDL dependencies.
 */
#ifndef SCRAM_FONTS_H
#define SCRAM_FONTS_H

#include "lvgl.h"

#define SCRAM_FONT_HERO  (&lv_font_montserrat_48)
#define SCRAM_FONT_VALUE (&lv_font_montserrat_24)
#define SCRAM_FONT_LABEL (&lv_font_montserrat_16)
#define SCRAM_FONT_SMALL (&lv_font_montserrat_12)

#endif /* SCRAM_FONTS_H */
