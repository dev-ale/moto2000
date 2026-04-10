/*
 * lv_conf.h — LVGL v9.2 configuration for the ScramScreen SDL simulator.
 *
 * Display: 466x466 round AMOLED (Waveshare 1.75").
 * Backend: SDL2 on macOS/Linux.
 */
#ifndef LV_CONF_H
#define LV_CONF_H

/* ---- Color ------------------------------------------------------------ */
#define LV_COLOR_DEPTH 32

/* ---- Memory ----------------------------------------------------------- */
#define LV_MEM_SIZE (256 * 1024)

/* ---- Display ---------------------------------------------------------- */
#define LV_HOR_RES_MAX 466
#define LV_VER_RES_MAX 466

/* ---- Tick ------------------------------------------------------------- */
#define LV_TICK_CUSTOM 0

/* ---- Draw backend ----------------------------------------------------- */
#define LV_USE_DRAW_SW 1

/* ---- SDL driver (built into LVGL v9) ---------------------------------- */
#define LV_USE_SDL 1

/* ---- OS layer --------------------------------------------------------- */
#define LV_USE_OS LV_OS_NONE

/* ---- Built-in fonts --------------------------------------------------- */
/* Enable the Montserrat sizes we need. These are placeholders until we
   generate custom Inter fonts via lv_font_conv. */
#define LV_FONT_MONTSERRAT_12 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_24 1
#define LV_FONT_MONTSERRAT_48 1

/* Default font for LVGL's internal use. */
#define LV_FONT_DEFAULT &lv_font_montserrat_16

/* ---- Widgets ---------------------------------------------------------- */
#define LV_USE_LABEL   1
#define LV_USE_ARC     1
#define LV_USE_BAR     1
#define LV_USE_LINE    1
#define LV_USE_IMAGE   1

/* ---- Misc ------------------------------------------------------------- */
#define LV_USE_ASSERT_NULL          1
#define LV_USE_ASSERT_MALLOC        1
#define LV_USE_ASSERT_OBJ           1

/* ---- Logging ---------------------------------------------------------- */
#define LV_USE_LOG 1
#define LV_LOG_LEVEL LV_LOG_LEVEL_WARN

#endif /* LV_CONF_H */
