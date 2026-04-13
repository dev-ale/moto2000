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

/* Sizes bumped for motorcycle glance-distance readability. The hero
 * label stays at the largest pre-rendered Montserrat (48 px) and is
 * scaled per-screen via lv_obj_set_style_transform_scale; everything
 * smaller than the hero just got promoted one tier. */
#define SCRAM_FONT_HERO  (&lv_font_montserrat_48)
#define SCRAM_FONT_VALUE (&lv_font_montserrat_36)
#define SCRAM_FONT_LABEL (&lv_font_montserrat_24)
#define SCRAM_FONT_SMALL (&lv_font_montserrat_20)

#endif /* SCRAM_FONTS_H */
