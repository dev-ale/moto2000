# Display Driver Component

LVGL display driver abstraction for the ScramScreen firmware. Provides a
platform-independent API (`display.h`) with two back-ends:

| Build target | Source files | Description |
|---|---|---|
| ESP-IDF (ESP32-S3) | `display_common.c` + `display_waveshare.c` | Real QSPI AMOLED driver |
| Host (macOS/Linux) | `display_common.c` + `display_stub.c` | No-op stub for testing |

## Public API

```c
int   display_init(void);                   // init hardware + LVGL display
int   display_set_brightness(uint8_t pct);  // 0-100%
void *display_get_lv_display(void);         // returns lv_display_t*
```

## Hardware: Waveshare ESP32-S3 1.75" Round AMOLED

- **Resolution:** 466 x 466 pixels (round)
- **Controller:** CO5300 (or compatible AMOLED driver)
- **Interface:** QSPI (4-wire SPI with quad data lines)
- **Color format:** RGB565 (16-bit) for bandwidth over QSPI

### Pin assignment

| Signal | GPIO | Notes |
|--------|------|-------|
| CS     | 6    | Chip select |
| CLK    | 47   | SPI clock |
| D0     | 18   | MOSI / SIO0 |
| D1     | 7    | SIO1 |
| D2     | 48   | SIO2 |
| D3     | 5    | SIO3 |
| RST    | 17   | Hardware reset (active low) |
| TE     | 9    | Tearing effect (vsync from panel) |

> **Important:** Verify these pins against your board revision's schematic.
> The pin numbers are sourced from the Waveshare wiki and example code.

### QSPI protocol notes

The CO5300 uses a QSPI command framing where:
1. An 8-bit command prefix (e.g., `0x02` for write) is sent on one line.
2. A 24-bit address field carries the DCS command byte.
3. Pixel/parameter data follows on all four quad lines.

The SPI bus runs at 40 MHz (conservative; up to 50 MHz per datasheet).

## Adapting for a different panel

1. Create a new `display_<panel>.c` alongside the Waveshare driver.
2. Implement `display_init()`, `display_set_brightness()`, and
   `display_get_lv_display()` using the panel's command set.
3. Reuse `display_create_lvgl()` from `display_common.c` for the LVGL
   display object setup.
4. Update `CMakeLists.txt` to select the correct source file (can be
   controlled via a Kconfig option or CMake variable).

## Testing

- **Host tests** (`test/host/test_display_stub.c`): Verify that
  `display.h` compiles cleanly and constants are correct. LVGL is not
  linked in the host-test harness, so the stub/common code is not
  exercised here.
- **LVGL simulator** (`lvgl-sim/`): Full LVGL integration testing with
  the real screen code. The stub driver can be wired in here.
- **On-device:** Flash to the Waveshare board and verify panel output.

## Assumptions documented with VERIFY comments

All hardware-specific values (pin numbers, SPI clock, command sequences,
address framing) are marked with `/* VERIFY: ... */` comments in the
source code. These must be validated during hardware bring-up.
