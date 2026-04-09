# BLE Protocol Fixtures

Golden binary fixtures + JSON descriptions for the ScramScreen BLE wire format.

Both the Swift `BLEProtocolTests` target and the C `test_ble_protocol` Unity binary
load these files and assert:

1. Decoding the `.bin` blob produces exactly the values in the matching `.json`.
2. Re-encoding those values produces byte-for-byte the original `.bin`.

## Layout

```
protocol/fixtures/
├── README.md               # this file
├── generate.py             # regenerates every .bin from its .json
├── valid/                  # well-formed packets that must decode successfully
│   ├── clock_basel_winter.bin
│   ├── clock_basel_winter.json
│   ├── nav_straight.bin
│   ├── nav_straight.json
│   ├── nav_sharp_left_basel.bin
│   ├── nav_sharp_left_basel.json
│   └── ...
└── invalid/                # malformed packets that must be rejected with a specific error
    ├── truncated_header.bin
    ├── truncated_header.json
    └── ...
```

## Regenerating

```sh
cd protocol/fixtures
python3 generate.py
```

This is the **authoritative** process: if a `.bin` diverges from its `.json`,
re-run the script and commit the fix. Hand-editing `.bin` files is forbidden.

## Adding a new fixture

1. Write the `.json` describing the packet.
2. Teach `generate.py` how to encode the relevant screen type (if new).
3. Run `python3 generate.py`.
4. Commit both the `.json` and `.bin`.
5. Both test suites pick it up automatically on the next run.
