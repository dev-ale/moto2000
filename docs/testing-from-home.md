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

## What doesn't work yet

- **LVGL host simulator + screen snapshot tests** — that is Slice 1.5b.
  Until it lands, you cannot yet render the actual ESP32 screens on your
  Mac. You *can* write all the logic that feeds them and verify it with
  unit tests.
- **BLE loopback transport** — also Slice 1.5b. Today the
  `ScenarioPlayer` drives iOS mock providers; once 1.5b is done, you'll be
  able to pipe the encoded BLE bytes into the host simulator and see the
  pixels.
- **Real data sources** — each real provider (wrapping `CLLocationManager`,
  `WeatherKit`, etc.) is added by its owning screen slice. Until then the
  protocols exist but the real implementations do nothing.
