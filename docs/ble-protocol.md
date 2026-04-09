# ScramScreen BLE Protocol

Status: **Draft v0** — finalized in Slice 1 (issue #2).

This document is the single source of truth for the BLE wire format between the iOS
companion app and the ESP32 firmware. The Swift encoder in
`app/ios/Packages/BLEProtocol/` and the C decoder in
`hardware/firmware/components/ble_protocol/` both derive their constants from this
spec and are validated against shared fixtures in `protocol/fixtures/`.

## Service

| Name | UUID |
|---|---|
| ScramScreen Service | `TBD` (128-bit, generated in Slice 1) |

## Characteristics

| Name | UUID | Properties | Direction | Purpose |
|---|---|---|---|---|
| `screen_data` | TBD | write, write-without-response | Phone → ESP32 | Screen payload — binary struct with screen ID + data fields |
| `control` | TBD | write | Phone → ESP32 | Commands: switch screen, set brightness, sleep/wake |
| `status` | TBD | notify, read | ESP32 → Phone | Device status: voltage, uptime, display state |

## Framing

All multi-byte integers are **little-endian**. Strings are UTF-8, null-terminated,
fixed-length unless noted otherwise. All writes begin with the common header:

```c
typedef struct __attribute__((packed)) {
    uint8_t  version;         // protocol version, currently 0x01
    uint8_t  screen_id;       // see Screen IDs table
    uint8_t  flags;           // bitfield — see Flags table
    uint8_t  reserved;        // must be 0
    uint16_t data_length;     // length of the following payload in bytes
    uint8_t  data[];          // screen-specific payload
} screen_payload_t;
```

## Screen IDs

| ID | Name | Status |
|---|---|---|
| `0x01` | Navigation | Slice 6 |
| `0x02` | Speed + Heading | Slice 3 |
| `0x03` | Compass | Slice 4 |
| `0x04` | Weather | Slice 7 |
| `0x05` | Trip Stats | Slice 9 |
| `0x06` | Music | Slice 8 |
| `0x07` | Lean Angle | Slice 10 |
| `0x08` | Blitzer / Radar | Slice 14 |
| `0x09` | Incoming Call | Slice 13 |
| `0x0A` | Fuel Estimate | Slice 12 |
| `0x0B` | Altitude Profile | Slice 15 |
| `0x0C` | Next Appointment | Slice 11 |
| `0x0D` | Idle / Clock | Slice 2 |

## Flags (bitfield)

| Bit | Name | Meaning |
|---|---|---|
| 0 | `ALERT` | This payload is an alert overlay with priority |
| 1 | `NIGHT_MODE` | Render in night palette |
| 2 | `STALE` | Data is stale — display accordingly |
| 3–7 | reserved | must be 0 |

## Control commands

Defined in Slice 5. Placeholder.

## Status notifications

Defined in Slice 2. Placeholder.

## Fixtures

Shared binary fixtures for round-trip tests live in
`protocol/fixtures/<screen_name>/`. Each fixture is a raw byte blob accompanied by a
`.json` description of its decoded contents.
