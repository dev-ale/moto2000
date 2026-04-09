# Ride Scenario Fixtures

Replayable ride scripts for development and testing without a real motorcycle.

Each scenario is a single JSON file conforming to the schema in
[`docs/scenarios.schema.json`](../../../../docs/scenarios.schema.json).
Supporting artefacts (GPX tracks, IMU traces, weather profiles) live next to
the JSON that references them and are merged into the scenario at load time
by tooling — **never hand-edit the `.json`**.

## Regenerating

```sh
cd app/ios/Fixtures/scenarios
python3 generate.py
```

This is the authoritative step. The script reads the GPX files and the IMU
CSVs, then writes the matching `.json` scenarios. If a scenario diverges
from its source data, re-run the script and commit the fix.

## Adding a new scenario

1. Drop a `.gpx`, a weather JSON patch, or an IMU CSV into this directory.
2. Teach `generate.py` to produce the new scenario file.
3. Run `python3 generate.py` and commit everything.

## Current fixtures

| Name | Summary |
|---|---|
| `basel-city-loop` | Short urban loop through central Basel, ~3 minutes, mixed speeds, one incoming call near the end |
| `highway-straight` | Steady 120 km/h highway run, clear weather, music playing |
