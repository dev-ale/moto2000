# ScramScreen host simulator

A standalone C project that builds on macOS and Linux (including
`ubuntu-latest` on GitHub Actions) and renders any ScramScreen screen
into a 466×466 PNG, driven by the **same** BLE payloads that the real
ESP32-S3 firmware decodes on device.

The simulator is the foundation of the "develop without a bike" workflow
described in [`docs/testing-from-home.md`](../../../docs/testing-from-home.md).
Together with:

- `RideSimulatorKit` (Slice 1.5a) — drives mock iOS data providers from a
  scenario file, then encodes each tick into a BLE payload via the
  `BLEProtocol` Swift package.
- `RideSimulatorKit/Transports/HostSimulatorBLETransport` (Slice 1.5b) —
  pipes those bytes into this simulator.
- `snapshots/*.png` (Slice 1.5b and beyond) — golden PNGs committed to
  git, diffed on every CI run.

…it forms a closed loop: change any screen's layout, re-run the snapshot
tests, see the diff, commit the new golden if it was intentional.

## ⚠️ Read this before judging the visual quality

**The PNGs this simulator produces are NOT what the real ESP32 screen will
look like.** They are intentionally rendered with an 8×8 pixel bitmap font
and a pure-C software rasteriser so that snapshot tests can diff PNGs
byte-for-byte across every CI runner and every developer's laptop. Any
anti-aliasing, font hinting, or vector rasterization would introduce
non-determinism and make snapshot tests flaky.

The real ESP32 firmware (starting at Slice 2, hardware bring-up) uses
**LVGL v9 with real TTF fonts** on the 466×466 round AMOLED, which runs
at ~267 PPI — comparable to an iPhone 4 Retina screen. Anti-aliased text,
smooth curves, proper typography. That is what the rider will actually
see. The mockups in [`docs/mockups.html`](../../../docs/mockups.html) are
the design target for the real device.

**Two renderers, two purposes:**

| Renderer | Lives where | Font | Purpose |
|---|---|---|---|
| Host simulator (this project) | `hardware/firmware/host-sim/` | 8×8 bitmap (`font8x8.h`) | CI-deterministic previews + snapshot regression tests |
| Real firmware (Slice 2+) | `hardware/firmware/main/` | LVGL v9 + TTF | What actually ships on the ESP32 |

If you see the simulator PNGs and think "that looks like a retro
calculator", you are right — and that is on purpose. Don't judge final
polish from these images; judge layout, information density, and
glanceability, which is what the snapshot tests are actually guarding.
See [`docs/adr/0003-lvgl-v9.md`](../../../docs/adr/0003-lvgl-v9.md) and
the "Graphics backend" section below for the full reasoning.

## Layout

```
host-sim/
├── CMakeLists.txt       # standalone project, reuses ble_protocol lib
├── cmake/               # CTest snapshot driver
├── include/host_sim/    # public headers (renderer, time_format)
├── src/                 # renderer, screen implementations, png writer
├── tests/               # Unity logic tests + snapshot_diff tool
├── tools/               # snapshot-update.sh
└── snapshots/           # committed golden PNGs
```

## Graphics backend — a judgement call

The issue tracker refers to this target as the **LVGL** host simulator.
Slice 1.5b ships a **pure-C software rasteriser** instead. Rationale:

- Offline, deterministic, and fast to build. No FetchContent of LVGL v9,
  no `lv_conf.h`, no SDL2, no fontconfig, no freetype. CI on
  `ubuntu-latest` just needs `build-essential` + `cmake`.
- Snapshot tests require **byte-identical** PNGs across every CI runner
  and every developer's laptop. Bringing in a real text shaper makes
  that substantially harder.
- The renderer is hidden behind the `host_sim_render_*` seam in
  [`renderer.h`](include/host_sim/renderer.h). A follow-up slice can
  swap the backend for real LVGL without touching `main.c`, the PNG
  writer, the snapshot harness, or the Swift `HostSimulatorBLETransport`.

When a future screen slice needs rich typography or anti-aliased vector
graphics that outgrow the 8×8 bitmap font, that's the moment to pull in
LVGL — probably as an **optional** backend selected at configure time so
CI can keep running the lightweight path.

## Build

```sh
cmake -S hardware/firmware/host-sim -B hardware/firmware/host-sim/build
cmake --build hardware/firmware/host-sim/build
```

This fetches two single-header stb libraries (`stb_image.h`,
`stb_image_write.h`) via `FetchContent` on first configure. It also
fetches Unity (same as the existing host-test project) for the
`test_host_sim_logic` unit tests. Both are pinned to explicit git SHAs /
tags for reproducibility.

## Run directly

The simulator reads the raw BLE payload (the exact bytes a BLE peer
would write to the firmware characteristic) from `--in` or stdin, and
writes a PNG to `--out`.

```sh
./build/scramscreen-host-sim \
    --in protocol/fixtures/valid/clock_basel_winter.bin \
    --out /tmp/clock.png
```

or via stdin:

```sh
./build/scramscreen-host-sim --out /tmp/clock.png \
    < protocol/fixtures/valid/clock_basel_winter.bin
```

Exit codes:

| code | meaning |
|------|---------|
| 0    | success |
| 2    | bad command line |
| 3    | cannot open `--in` file |
| 4    | cannot read payload |
| 5    | empty payload |
| 6    | out of memory |
| 7    | cannot write PNG to `--out` |
| 12+  | payload decoded but rendering reported an error |

## Tests

```sh
ctest --test-dir hardware/firmware/host-sim/build --output-on-failure
```

There are two kinds of tests:

1. **`test_host_sim_logic`** — Unity unit tests for the pure-C helpers
   in `time_format.c`. These keep clock/date formatting free of host
   zoneinfo, locale, and `TZ` environment sensitivity so snapshot tests
   stay deterministic.
2. **`snapshot_*`** — end-to-end tests that run
   `scramscreen-host-sim` against a committed fixture in
   `protocol/fixtures/valid/`, write a fresh PNG under `build/snapshot-out/`,
   and pixel-diff it against the committed golden in `snapshots/`. Any
   difference fails the test loudly (the CMake driver prints the worst
   pixel delta and the golden path).

## Regenerating goldens

When a screen's layout changes on purpose:

```sh
hardware/firmware/host-sim/tools/snapshot-update.sh
git diff -- hardware/firmware/host-sim/snapshots/
```

**Review the visual diff before committing.** Snapshot tests only catch
regressions if someone actually looks at the new PNG. See
[`docs/testing-from-home.md`](../../../docs/testing-from-home.md) for
the full workflow.

## Adding a new screen

1. Add a `host_sim_render_<screen>` function in a new file under `src/`.
2. Dispatch to it in `host_sim_render_payload()` in `renderer.c`.
3. Add the new file to `CMakeLists.txt`.
4. Add a fixture to `protocol/fixtures/valid/` (most already exist).
5. Add an `add_snapshot_test(<name> <fixture>)` call to
   `CMakeLists.txt` and a matching entry in `tools/snapshot-update.sh`.
6. Run `snapshot-update.sh`, review, commit.

Every screen slice's definition of done includes a snapshot test.
