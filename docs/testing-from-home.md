# Testing from home

You do not need a motorcycle, a GPS fix, an iPhone outside, or a real ESP32
to develop ScramScreen. This document explains the workflow.

## The idea

Every iOS data source (`CoreLocation`, `CLHeading`, `CoreMotion`,
`WeatherKit`, `MPNowPlayingInfoCenter`, `CXCallObserver`, `EventKit`) sits
behind a Swift protocol with a real implementation and a **scenario-driven
mock**. A scenario is a JSON file that describes a timeline of events. The
`ScenarioPlayer` loads a scenario and drives every mock provider in lock
step, so the rest of the app believes it is on a real ride.

See [`scenarios.md`](./scenarios.md) for the file format and
[`app/ios/Packages/RideSimulatorKit/`](../app/ios/Packages/RideSimulatorKit)
for the implementation.

## Workflow: run a pre-recorded ride

1. Build the app in **Debug**.
2. Launch it. The placeholder root view shows a **Ride Simulator** button
   only in Debug — `#if DEBUG` wraps the entire picker so Release builds
   cannot see it.
3. Pick one of the bundled scenarios
   (e.g. `basel-city-loop` or `highway-straight`).
4. Pick a playback speed (1× / 5× / 10× / 60×).
5. Press **Play**. Every mock provider starts emitting samples as if a real
   ride were in progress. Any screen that consumes the provider protocols
   will see the data.

## Workflow: iterate on a screen without a bike

1. Write the screen's real provider implementation behind the protocol.
2. Write the screen's unit tests against the **mock** provider, feeding
   samples from a scenario or a hand-built fixture.
3. Run `swift test` from the SwiftPM package. Tests use a `VirtualClock`
   that advances instantly — a full 30-minute scenario completes in
   milliseconds and is deterministic.
4. When the tests pass, launch the app in Debug and replay the same scenario
   through the picker to see it live on device (or simulator).

## Workflow: record a new scenario from a real ride

_(A recording button is not yet in the dev UI. Tests already exercise
`ScenarioRecorder` directly; the button lands in a follow-up.)_

The plan:

1. Open the dev-only panel, tap **Record**, and ride.
2. On stop, the app writes a scenario JSON to the app's documents
   directory.
3. Drop that file into `app/ios/Fixtures/scenarios/`, commit, done — every
   future test can replay it.

## Workflow: regenerate a fixture after editing a GPX

```sh
cd app/ios/Fixtures/scenarios
python3 generate.py
```

Never hand-edit the `.json` files. `generate.py` is authoritative.

## Workflow: render a screen on your Mac (no bike, no ESP32)

Slice 1.5b ships a standalone C host simulator that decodes the **exact
same** BLE payload bytes the firmware decodes on device and writes a
466×466 PNG of the corresponding screen.

```sh
cmake -S hardware/firmware/host-sim -B hardware/firmware/host-sim/build
cmake --build hardware/firmware/host-sim/build
./hardware/firmware/host-sim/build/scramscreen-host-sim \
    --in protocol/fixtures/valid/clock_basel_winter.bin \
    --out /tmp/clock.png
open /tmp/clock.png
```

See [`hardware/firmware/host-sim/README.md`](../hardware/firmware/host-sim/README.md)
for the full CLI, error codes, and the judgement call behind the pure-C
software rasteriser (vs. a FetchContent-driven LVGL+SDL backend).

## Workflow: loopback from Swift into the simulator

`RideSimulatorKit` ships a `BLETransport` protocol and a
`HostSimulatorBLETransport` that spawns the host simulator as a
subprocess and pipes encoded payloads into its stdin:

```swift
let transport = HostSimulatorBLETransport(
    executableURL: URL(fileURLWithPath: "…/host-sim/build/scramscreen-host-sim"),
    outputURL: URL(fileURLWithPath: "/tmp/loopback.png")
)
let payload = ScreenPayload.clock(clockData, flags: [])
try await transport.send(ScreenPayloadCodec.encode(payload))
```

The `testEndToEndLoopbackAgainstRealSimulator` XCTest exercises the
whole path. It auto-skips unless `SCRAMSCREEN_HOST_SIM` points at the
built simulator, so it is safe to leave committed:

```sh
cd app/ios/Packages/RideSimulatorKit
SCRAMSCREEN_HOST_SIM=$(pwd)/../../../../hardware/firmware/host-sim/build/scramscreen-host-sim \
    swift test --filter BLETransportTests
```

When Slice 2 lands a real Core Bluetooth transport, the only thing that
changes is which `BLETransport` implementation the scenario player
injects. Every screen test written against the host-simulator transport
stays unchanged.

## Workflow: screen snapshot tests

Every future screen slice ships a committed golden PNG under
`hardware/firmware/host-sim/snapshots/` plus an `add_snapshot_test()`
entry in `hardware/firmware/host-sim/CMakeLists.txt`. The ctest harness
runs the simulator against a fixture, writes a PNG, and pixel-diffs it
against the golden via a small stb_image based `snapshot-diff` helper.

```sh
cd hardware/firmware/host-sim
cmake -B build && cmake --build build
ctest --test-dir build --output-on-failure
```

CI runs the same thing on `ubuntu-latest` in the new `host-sim` job in
`.github/workflows/firmware.yml`.

When an intentional UI change lands, regenerate the goldens:

```sh
./hardware/firmware/host-sim/tools/snapshot-update.sh
git diff -- hardware/firmware/host-sim/snapshots/
```

**Always review the visual diff before committing.** A snapshot test
only catches regressions if a human actually looked at the new PNG.

## Watch a ride play out as a video

`tools/scenario-to-video` walks a scenario JSON second-by-second, feeds
each derived state through the host simulator, and stitches the PNGs into
an MP4 with ffmpeg. This gives you a playable video of the dashboard
reacting to the ride — no bike, no ESP32, no iPhone.

Prerequisites:

1. Build the host simulator
   (`cmake -B hardware/firmware/host-sim/build && cmake --build hardware/firmware/host-sim/build`).
2. Install ffmpeg (`brew install ffmpeg` on macOS, `apt-get install ffmpeg`
   on Ubuntu).

Then from the repo root:

```sh
cd tools/scenario-to-video
swift build -c release
.build/release/scenario-to-video \
    --scenario ../../app/ios/Fixtures/scenarios/basel-city-loop.json \
    --host-sim ../../hardware/firmware/host-sim/build/scramscreen-host-sim \
    --out /tmp/basel.mp4 \
    --verbose
open /tmp/basel.mp4
```

See `tools/scenario-to-video/README.md` for every flag, the list of
derivable screens, and troubleshooting tips. This tool is **not** part of
CI — it is a manual developer utility.

## Workflow: switch screens from the iOS app

Slice 5 ships a debug-only **Screen Picker** sheet next to the existing
Ride Simulator panel on the iOS app's `RootView`. It's wrapped in
`#if DEBUG` so it never lands in a Release build.

To exercise it without an ESP32 attached:

1. Run the ScramScreen iOS target on a simulator or device
   (`tuist generate && open ScramScreen.xcworkspace`).
2. Tap **Screen Picker** on the launch screen.
3. Pick a row to send a `setActiveScreen` `ControlCommand` over the
   `control` characteristic. The "Last command" footer echoes the action
   for sanity.
4. Drag the brightness slider and tap **Apply** for `setBrightness`.
5. The **Power** section sends `sleep`, `wake`, and `clearAlertOverlay`.

The picker drives a `ScreenPickerViewModel` from
`Packages/ScramCore/Sources/ScramCore/Control/`. The view itself is a
trivial wrapper — every behaviour (selection, reorder, enable/disable,
persistence) is unit-tested in `ScramCorePackageTests` without bringing in
SwiftUI.

The 500 ms Slice 5 success criterion (write → render) decomposes into
roughly:

- iOS-side validate / encode / queue:   < 5 ms (`ScreenControllerLatencyTests`)
- BLE round trip + ack on a typical link: ~150 ms
- ESP32 parse / FSM / render:            ~200 ms

The first region is the only piece this slice owns; the other two are
covered by the firmware integration tests and the device bring-up report.

## Workflow: test night mode via the dev panel

Slice 16 adds a `NightModeService` that automatically toggles night mode
based on time-of-day or ambient light. To test it without waiting for
sunset:

1. **Force night mode via user override.** In the debug panel, the
   brightness section will gain a "Force Night" / "Force Day" / "Auto"
   segmented control (once the SwiftUI view lands). In tests, call:
   ```swift
   await nightModeService.setUserOverride(.autoWithNightMode)
   ```

2. **Inject fake lux samples.** Use `MockAmbientLightProvider` to emit
   low-lux samples:
   ```swift
   let mockLight = MockAmbientLightProvider()
   mockLight.emit(AmbientLightSample(lux: 10, timestamp: Date()))
   ```
   The service picks up the sample and switches to night mode within one
   evaluation cycle (< 1 s in tests, 60 s in production).

3. **Render via the host simulator.** Pass any fixture `.bin` with the
   `NIGHT_MODE` flag set to the host-sim:
   ```sh
   ./hardware/firmware/host-sim/build/scramscreen-host-sim \
       --in protocol/fixtures/valid/speed_urban_45kmh_night.bin \
       --out /tmp/speed_night.png
   open /tmp/speed_night.png
   ```

4. **Run snapshot tests.** The night-mode snapshot tests verify the red
   palette renders correctly for speed, compass, navigation, and clock:
   ```sh
   ctest --test-dir hardware/firmware/host-sim/build -R night
   ```

## What doesn't work yet

- **Real data sources** — each real provider (wrapping `CLLocationManager`,
  `WeatherKit`, etc.) is added by its owning screen slice. Until then the
  protocols exist but the real implementations do nothing.
- **Real BLE transport** — Slice 2 replaces the loopback transport with
  a Core Bluetooth peripheral wrapper. Until then, scenarios driven
  through `HostSimulatorBLETransport` render on your Mac, not on the
  actual ESP32 panel.
