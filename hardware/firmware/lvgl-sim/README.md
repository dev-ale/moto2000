# ScramScreen LVGL Simulator

A standalone CMake project that renders the 466x466 round AMOLED display
in an SDL2 window on macOS (and Linux) using real LVGL v9.2. This is the
**production UI code** that will flash to the ESP32 unchanged.

## How it differs from `host-sim/`

| Aspect           | `host-sim/`                          | `lvgl-sim/`                         |
|------------------|--------------------------------------|-------------------------------------|
| **Purpose**      | CI snapshot tests                    | Design iteration + production code  |
| **Rendering**    | Bitmap font software rasteriser      | LVGL v9 with anti-aliased fonts     |
| **Output**       | Headless PNG                         | SDL2 window (interactive)           |
| **Determinism**  | Byte-identical across platforms      | Visual output may vary slightly     |
| **Fonts**        | 5x8 bitmap font                     | Montserrat (placeholder for Inter)  |
| **ESP32 compat** | N/A (host-only tool)                | Screen `.c` files compile unchanged |

Both projects read the same BLE payload format via `ble_protocol`.

## Prerequisites

```sh
brew install sdl2 cmake    # macOS
apt install libsdl2-dev     # Linux (Debian/Ubuntu)
```

## Build

```sh
cmake -S hardware/firmware/lvgl-sim -B hardware/firmware/lvgl-sim/build
cmake --build hardware/firmware/lvgl-sim/build
```

## Run

**One-shot mode** (render a fixture, view in SDL window, press Q to quit):

```sh
./hardware/firmware/lvgl-sim/build/scramscreen-lvgl-sim \
    --in protocol/fixtures/valid/clock_basel_winter.bin
```

**Live mode** (accept hex-encoded payloads on stdin):

```sh
./hardware/firmware/lvgl-sim/build/scramscreen-lvgl-sim --live
```

Then paste hex-encoded BLE payloads (one per line) to re-render.

## Adding a new screen

1. Create `screens/screen_foo.h` and `screens/screen_foo.c`.
   - The header declares `void screen_foo_create(lv_obj_t *parent, const ble_foo_data_t *data, uint8_t flags);`
   - The `.c` file uses only LVGL APIs (no SDL). It must compile on ESP32.
2. Add the decode + dispatch case in `common/screen_manager.c`.
3. Add the `.c` file to `CMakeLists.txt`.
4. Test with the appropriate fixture from `protocol/fixtures/valid/`.

## Font replacement

The simulator currently uses LVGL's built-in Montserrat fonts. See
`fonts/README.md` for instructions on generating custom Inter fonts
via `lv_font_conv`.

## Night mode

Pass any fixture with the `NIGHT_MODE` flag set (e.g.
`clock_night_mode.bin`) to see the red-on-black palette.

## Architecture

```
main.c           SDL init, LVGL init, event loop (SDL-specific)
theme/           Custom theme + color palette (ESP-IDF compatible)
screens/         Screen implementations (ESP-IDF compatible)
common/          Screen manager dispatch (ESP-IDF compatible)
fonts/           Font files + generation docs
lv_conf.h        LVGL configuration
```

Only `main.c` contains SDL-specific code. Everything else uses pure
LVGL APIs and will compile on the ESP32 without changes.
