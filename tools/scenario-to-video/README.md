# scenario-to-video

Turn a ScramScreen scenario JSON file into an MP4 of the dashboard reacting
to the simulated ride, without touching a real ESP32.

This tool is a developer utility — it is **not** wired into CI. It exists so
the owner can watch a scenario play out at their desk.

## How it works

```
scenario.json
      │  (ScenarioLoader)
      ▼
FrameBuilder ──── one ScreenPayload per simulated second
      │
      │  (ScreenPayloadCodec.encode)
      ▼
BLE bytes ──────▶ scramscreen-host-sim ──▶ frame-000000.png
                                           frame-000001.png
                                           ...
                                           │
                                           ▼
                                          ffmpeg ──▶ ride.mp4
```

The host simulator is the same desktop binary used for snapshot tests, so
the frames you see in the video are byte-for-byte what the ESP32 would
render from the same BLE payload.

## Prerequisites

1. **Host simulator built.** From the repo root:
   ```sh
   cd hardware/firmware/host-sim
   cmake -B build && cmake --build build
   # Binary lands at hardware/firmware/host-sim/build/scramscreen-host-sim
   ```
2. **ffmpeg installed.**
   - macOS: `brew install ffmpeg`
   - Ubuntu: `sudo apt-get install -y ffmpeg`

## Usage

```sh
cd tools/scenario-to-video
swift build -c release

.build/release/scenario-to-video \
    --scenario ../../app/ios/Fixtures/scenarios/basel-city-loop.json \
    --host-sim ../../hardware/firmware/host-sim/build/scramscreen-host-sim \
    --out /tmp/basel.mp4 \
    --verbose
```

### Flags

| Flag             | Default    | Meaning                                              |
|------------------|------------|------------------------------------------------------|
| `--scenario`     | required   | Path to scenario JSON.                               |
| `--host-sim`     | required   | Path to `scramscreen-host-sim`.                      |
| `--out`          | required   | Where to write the MP4.                              |
| `--ffmpeg`       | `ffmpeg`   | Explicit ffmpeg path (else resolved from `$PATH`).   |
| `--screen`       | `speed`    | `speed`, `clock`, or `rotate`.                       |
| `--fps`          | `1`        | Frames per simulated second.                         |
| `--keep-frames`  | off        | Keep the intermediate PNG directory.                 |
| `--verbose`      | off        | Log every frame to stderr.                           |

### Screen selection

`--screen` picks which dashboard view to render for every frame:

- `speed` — speed + heading screen (default). Recommended for ride videos.
- `clock` — synthesised clock, useful for smoke-testing the pipeline.
- `rotate` — alternates between clock and speed every 10 simulated seconds.

Only these two screens are derived from scenario data today. Deriving the
other screens (compass, nav, weather, trip, music, etc.) is future work;
when their wire formats land in `BLEProtocol`, `FrameBuilder` can grow more
cases.

### TODO

- Default behaviour when `--screen` is omitted should cycle through every
  supported screen automatically (the spec calls this "rotating demo
  mode"). Today it defaults to `speed` only. Pass `--screen rotate` for a
  two-screen alternation.
- Populate temperature in `speedHeading` frames from `weatherSnapshots`.
- Derive compass frames once `BLEProtocol` gains a compass payload.

## Troubleshooting

- **`ffmpeg not found`** — install ffmpeg (see above) or pass `--ffmpeg
  /absolute/path/to/ffmpeg`.
- **`host-sim failed on frame N`** — rebuild the host simulator; the tool
  reports the underlying stderr in the error message.
- **Empty output / zero frames** — the scenario has `durationSeconds == 0`.
  Scenario-to-video always emits at least one frame, so check that the
  scenario itself is non-trivial.

## Testing

```sh
swift test
```

Unit tests cover:

- Frame derivation from synthetic scenarios (empty, single-sample, gaps,
  out-of-range speed/heading, rotating screens, round-trip encode/decode).
- Hand-rolled CLI parser (all flags, required-flag errors, invalid fps,
  help exit code).
- `SimRunner` error path when the host-sim binary is missing.
- `VideoEncoder` ffmpeg argv construction and `$PATH` resolution.

End-to-end video generation is **not** exercised in tests — it is verified
manually by running the example invocation above. The real-subprocess
`SimRunner` test is gated on the `SCRAMSCREEN_HOST_SIM` env var, same as
the BLE transport tests in `RideSimulatorKit`.
