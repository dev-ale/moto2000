# Ride Scenarios

A **scenario** is a replayable ride: a single JSON file describing a timeline
of GPS samples, heading, motion, weather, music, calls, and calendar events.
Scenarios let you develop and test every dashboard screen without a bike,
without a GPS fix, and without a BLE peripheral.

## Where scenarios live

```
app/ios/Fixtures/scenarios/
├── README.md
├── generate.py              # authoritative generator
├── <name>.json              # scenario file
├── <name>.gpx               # optional GPX source track
├── <name>.weather.json      # optional weather patch
└── <name>.imu.csv           # optional IMU samples
```

The `.json` file is the on-disk wire format. The supporting artefacts (GPX,
CSV) exist so we can hand-edit the source data in the format that best suits
each kind of signal — XML for tracks, CSV for time-series sensors — and let
`generate.py` compile them into the final JSON.

**Never hand-edit the `.json`.** Run `python3 generate.py` instead.

## File format

The Swift source of truth is
[`Scenario.swift`](../app/ios/Packages/RideSimulatorKit/Sources/RideSimulatorKit/Scenarios/Scenario.swift)
and the machine-readable schema is [`scenarios.schema.json`](./scenarios.schema.json).

Minimal valid scenario:

```json
{
  "version": 1,
  "name": "empty",
  "summary": "",
  "durationSeconds": 0,
  "locationSamples": [],
  "headingSamples": [],
  "motionSamples": [],
  "weatherSnapshots": [],
  "nowPlayingSnapshots": [],
  "callEvents": [],
  "calendarEvents": []
}
```

Every sample and event carries a `scenarioTime` in seconds since the scenario
started. The `ScenarioPlayer` merges them into one time-sorted timeline and
emits them in order relative to its clock, so the file format does not care
which order the arrays are in.

### Versioning

The top-level `version` field is currently `1`. Bumping it is a breaking
change: the Swift decoder rejects unknown versions and `generate.py` must be
updated in the same commit.

## Playing a scenario

### From tests

```swift
let scenario = try ScenarioLoader.load(from: fixtureURL)
let env = SimulatorEnvironment()
let clock = VirtualClock()
let player = ScenarioPlayer(environment: env, clock: clock)

// Drive the clock forward deterministically.
Task { await player.play(scenario) }
await clock.advance(to: scenario.durationSeconds + 1)
```

`VirtualClock` advances instantly, so a 30-minute scenario runs in
milliseconds and produces deterministic output — perfect for CI.

### From the dev build

Launch the app in Debug, tap **Ride Simulator** on the placeholder root view,
pick a scenario, pick a speed (1× / 5× / 10× / 60×), and press **Play**.
Behind the scenes the app uses a `WallClock` configured by the speed
multiplier so 1× is realtime and 60× replays a 1-hour ride in 1 minute.

The picker is compiled out of Release builds via `#if DEBUG`.

## Recording a scenario

`ScenarioRecorder` captures events from the real providers into a new
scenario. Usage from the dev build will be added in the recording UI in a
follow-up; tests today exercise the recorder directly:

```swift
let clock = VirtualClock()
let recorder = ScenarioRecorder(clock: clock, name: "my-ride")
await recorder.start()
// ... provider events arrive ...
await recorder.record(sampleFromRealProvider)
let scenario = await recorder.stop()
try ScenarioLoader.save(scenario, to: someURL)
```

## Definition of done for future slices

From Slice 1.5a onward, every screen slice must ship:

1. A scenario fixture that exercises the screen
2. A test that replays the fixture through the scenario player
3. A note in its PR description explaining how a reviewer can verify the
   screen from the ride simulator without a bike

Slice 1.5b will add host-simulator snapshot tests on top of this.

## Replaying a scenario through the navigation pipeline

From Slice 6 onward, any scenario with `locationSamples` can be replayed
through `NavigationService` to produce a `nav_data_t` stream. Tests wire
a `StaticRouteEngine` (fed from a hand-crafted `*.route.json` fixture)
to the scenario's `MockLocationProvider` so no MapKit or CoreLocation is
touched. See `NavigationIntegrationTests.test_replayBaselCityLoop_*`
for the pattern.
