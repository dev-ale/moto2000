# ScramScreen Firmware — Main Component

This is the ESP-IDF `app_main` entry point that wires all firmware components
together for the ScramScreen motorcycle dashboard.

## Boot Sequence

1. **NVS** — `nvs_flash_init()` (required by NimBLE for bonding storage)
2. **State machines** — `screen_fsm_init`, `ble_reconnect_init`, `ble_payload_cache_init`
3. **LVGL core** — `lv_init()`
4. **Display driver** — `display_init()` (QSPI AMOLED on Waveshare ESP32-S3)
5. **LVGL tick timer** — 5 ms periodic `esp_timer` calling `lv_tick_inc(5)`
6. **Theme** — `scram_theme_apply()` (dark theme with night-mode toggle)
7. **Screen manager** — `screen_manager_init()` (creates initial clock screen)
8. **Brightness** — `display_set_brightness(80)`
9. **BLE server** — `ble_server_init()` + `ble_server_start_advertising()`
10. **Main loop** — `lv_timer_handler()` + `vTaskDelay()`

## Component Dependency Graph

```
app_main
  |
  +-- ble_server          (NimBLE GATT, callbacks)
  |     +-- ble_server_handlers  (pure-C dispatch)
  |           +-- ble_protocol   (wire format codec)
  |           +-- screen_fsm     (screen switching + alert overlays)
  |           +-- ble_reconnect  (reconnect FSM + payload cache)
  |
  +-- display             (QSPI AMOLED driver + LVGL display object)
  +-- lvgl                (graphics library)
  +-- screen_manager      (dispatches payloads to screen implementations)
  +-- scram_theme         (LVGL theme)
  +-- screens/*           (14 LVGL screen implementations from lvgl-sim/)
```

## Main Loop

The main loop runs on the default FreeRTOS task (priority 1). It calls
`lv_timer_handler()` which processes all pending LVGL timers, animations, and
input events, then yields to FreeRTOS for the duration LVGL recommends (minimum
5 ms). BLE callbacks run on the NimBLE host task and update the shared state
machines directly; LVGL rendering happens only in the main loop.

## LVGL Screen Inclusion Strategy

The 14 screen `.c` files live in `hardware/firmware/lvgl-sim/screens/` and are
shared between the SDL simulator and the ESP-IDF firmware. They use only LVGL
APIs (no SDL). The `main/CMakeLists.txt` compiles them directly into the
firmware by listing them as SRCS with relative paths to `../lvgl-sim/`. The
simulator's `main.c` (SDL entry point) is never included.

## Testing

The host-side integration test at `test/host/test_integration.c` exercises the
full dispatch wiring (BLE payload -> handlers -> FSMs -> cache) without LVGL or
ESP-IDF dependencies. Run it with:

```sh
cd hardware/firmware/test/host
cmake -B build && cmake --build build
ctest --test-dir build --output-on-failure
```
