# Font generation for the LVGL simulator

The ScramScreen LVGL simulator currently uses LVGL's built-in **Montserrat**
fonts as placeholders. For production quality, replace them with the
**Inter** font family (open source, excellent for dashboards).

## Font size mapping

| Alias            | Placeholder         | Target                 | Use case                          |
|------------------|---------------------|------------------------|-----------------------------------|
| `SCRAM_FONT_HERO`  | Montserrat 48    | Inter Bold 48          | Hero digits (speed, time)         |
| `SCRAM_FONT_VALUE` | Montserrat 24    | Inter Medium 24        | Secondary values (heading, temp)  |
| `SCRAM_FONT_LABEL` | Montserrat 16    | Inter Regular 16       | Labels, units                     |
| `SCRAM_FONT_SMALL` | Montserrat 12    | Inter Regular 12       | Small metadata                    |

## How to generate Inter fonts

1. Download **Inter** from https://rsms.me/inter/ (or Google Fonts).

2. Install `lv_font_conv`:
   ```sh
   npm install -g lv_font_conv
   ```

3. Generate each font:
   ```sh
   npx lv_font_conv \
       --font Inter-Bold.ttf --size 48 --bpp 4 \
       --format lvgl -o inter_bold_48.c \
       --range 0x20-0x7F,0xB0

   npx lv_font_conv \
       --font Inter-Medium.ttf --size 24 --bpp 4 \
       --format lvgl -o inter_medium_24.c \
       --range 0x20-0x7F,0xB0

   npx lv_font_conv \
       --font Inter-Regular.ttf --size 16 --bpp 4 \
       --format lvgl -o inter_regular_16.c \
       --range 0x20-0x7F,0xB0,0xC4,0xD6,0xDC,0xE4,0xF6,0xFC

   npx lv_font_conv \
       --font Inter-Regular.ttf --size 12 --bpp 4 \
       --format lvgl -o inter_regular_12.c \
       --range 0x20-0x7F,0xB0
   ```

   The `0xB0` range adds the degree symbol. The 16pt font also includes
   German umlauts (used in location names on some screens).

4. Place the generated `.c` files in this directory.

5. Update `lv_conf.h`:
   - Add `LV_FONT_CUSTOM_DECLARE` entries for each font.
   - Optionally disable the Montserrat fonts you no longer need.

6. Update `theme/scram_fonts.h` to point at the new font symbols:
   ```c
   LV_FONT_DECLARE(inter_bold_48);
   #define SCRAM_FONT_HERO  (&inter_bold_48)
   ```

7. Add the `.c` files to `CMakeLists.txt` in the executable sources.

## Notes

- `--bpp 4` gives 16 levels of anti-aliasing (good quality vs. size).
- Keep the glyph range minimal for embedded targets. Add Unicode blocks
  as needed when internationalisation lands.
- The same fonts are used on both the SDL simulator and ESP32 firmware.
