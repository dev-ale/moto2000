# Night mode and brightness control

ScramScreen automatically adjusts display brightness and activates a
red-on-black "night mode" palette to preserve dark-adapted vision during
night rides.

## Decision hierarchy

The `BrightnessPolicy` pure function evaluates inputs in this order:

1. **User override** — the rider can force a specific brightness
   percentage, force night mode on, or force day mode on via the dev
   panel (and eventually a physical button or app gesture).
2. **Ambient light sensor** — if a lux reading is available:
   - < 50 lux: night mode ON, brightness scaled linearly (0 lux = 10%,
     50 lux = 50%).
   - 50-200 lux: transition zone, day mode, brightness 50-100%.
   - >= 200 lux: day mode, brightness 100%.
3. **Time-based fallback** — if no sensor is available, the policy uses
   sunrise/sunset times computed from GPS coordinates:
   - Before sunrise or after sunset + 30 min: night mode ON, 30%.
   - Within 30 min of sunrise/sunset (twilight): night mode ON, 50%.
   - Daytime: day mode, 100%.

## Sunrise/sunset calculator

`SunriseSunsetCalculator` implements a simplified NOAA solar position
algorithm as a pure function. Inputs: latitude, longitude, date, timezone
offset. Outputs: sunrise and sunset as UTC `Date` values.

Accuracy: +/-5 minutes for mid-latitudes. Handles polar edge cases:
- **Midnight sun** (cosHA < -1): returns a full-day window.
- **Polar night** (cosHA > 1): returns sunrise == sunset at solar noon.

## Wire protocol

Night mode uses two existing mechanisms from Slice 5:

- `ControlCommand.setBrightness(UInt8)` — sent over the BLE `control`
  characteristic. The ESP32 will use this to drive AMOLED PWM (deferred).
- `ScreenFlags.nightMode` — bit 1 in the header flags byte of every
  `screen_data` payload. The host-sim renderer reads this and switches
  to the red palette. The real LVGL firmware will do the same (deferred).

No new BLE payload types were introduced.

## Architecture

```
LocationProvider ──┐
                   ├─▶ NightModeService (actor)
AmbientLightProvider ─┤     │
                      │     ├─▶ SunriseSunsetCalculator (pure)
  dateProvider() ─────┘     ├─▶ BrightnessPolicy.decide() (pure)
                            │
                            ├─▶ commands: AsyncStream<Data>  (setBrightness)
                            └─▶ isNightMode: Bool  (read by screen services)
```

The `NightModeService` re-evaluates every 60 seconds and on each new
ambient light sample. It emits a `setBrightness` command only when the
decision changes.

## Ambient light provider

`AmbientLightProvider` is a protocol with:

- `MockAmbientLightProvider` — emits scripted samples for tests.
- `SystemAmbientLightProvider` — **stub** (iOS only), emits nothing.

iOS does not expose a public ambient light sensor API. Future options:
1. `UIScreen.main.brightness` as a proxy (imprecise, zero-permission).
2. Camera-based lux estimation via AVCaptureDevice metadata.
3. External BLE lux sensor (e.g. TSL2591 breakout board).

Until one of these ships, the app falls back to time-based decisions.

## Deferred to hardware slices

- **ESP32 PWM brightness control** — the `setBrightness` command is
  sent but the firmware does not yet drive the AMOLED backlight via the
  `ledc` driver.
- **LVGL palette swap on real firmware** — the host-sim already renders
  night mode; the real firmware needs the same colour table switch.
- **PWM range verification on device** — needs the physical AMOLED panel.
- **Real ambient light sensor** — see above.

## Testing

### Swift unit tests (ScramCore)

```sh
cd app/ios/Packages/ScramCore
swift test --filter "SunriseSunsetCalculator|BrightnessPolicy|NightModeService"
```

- `SunriseSunsetCalculatorTests` — Basel summer/winter, Tromso midnight
  sun, equator equinox (5 tests).
- `BrightnessPolicyTests` — all branches of the decision hierarchy
  (10 tests).
- `NightModeServiceTests` — midnight/noon in Basel, lux override, user
  override, decision change detection (5 tests).

### Host-sim snapshot tests

```sh
ctest --test-dir hardware/firmware/host-sim/build -R night
```

Four night-mode snapshot tests: clock, speed, compass, navigation.
