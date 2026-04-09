# ScramScreen BLE Protocol

**Version:** 1
**Status:** Stable — defined in Slice 1 (#2). Breaking changes require bumping the
`version` byte and updating every fixture under `protocol/fixtures/`.

This document is the single source of truth for the BLE wire format between the iOS
companion app and the ESP32 firmware. The Swift encoder in
`app/ios/Packages/BLEProtocol/` and the C codec in
`hardware/firmware/components/ble_protocol/` both derive their constants from this
spec and are validated against shared golden fixtures in `protocol/fixtures/`.

## Service

| Name | UUID |
|---|---|
| ScramScreen Service | `b6ca8101-b172-4d33-8518-8b1700235ed2` |

## Characteristics

| Name | UUID | Properties | Direction | Purpose |
|---|---|---|---|---|
| `screen_data` | `3ad9d5d0-1d70-4edf-b2cc-bf1d84dc545b` | write, write-without-response | Phone → ESP32 | Screen payload — header + screen-specific body |
| `control`     | `160c1f54-82ec-45e2-8339-1680f16c1a94` | write                          | Phone → ESP32 | Control commands (defined in Slice 5) |
| `status`      | `b7066d36-d896-4e74-9648-500df789d969` | notify, read                   | ESP32 → Phone | Device status (defined in Slice 2) |

## Wire format

All multi-byte integers are **little-endian**. Strings are UTF-8, zero-padded to a
fixed length, and must include a terminating `0x00` byte — if the string is shorter
than the field, bytes after the terminator are ignored on decode and must be zero on
encode.

Every write to `screen_data` begins with the common 8-byte header:

```
 0               1               2               3
 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|    version    |   screen_id   |     flags     |   reserved    |
+---------------+---------------+---------------+---------------+
|         data_length           |     body (variable length)    |
+-------------------------------+-------------------------------+
```

| Field | Type | Notes |
|---|---|---|
| `version` | `uint8` | Protocol version. Current: `0x01`. Decoders must reject unknown versions. |
| `screen_id` | `uint8` | See Screen IDs table. |
| `flags` | `uint8` | See Flags bitfield. |
| `reserved` | `uint8` | Must be `0x00` on encode. Decoders must reject non-zero. |
| `data_length` | `uint16` | Length of the body in bytes. Must equal the expected body length for the given `screen_id`. |
| `body` | bytes | Screen-specific payload. |

Total header size: **8 bytes**. Minimum packet size: 8 bytes (empty body, e.g. a
clock screen that sends only the body below — still non-empty).

### Framing rules

- Encoders must emit `version = 0x01`, `reserved = 0x00`, and `data_length` equal
  to `body.count`.
- Decoders must fail with a clear error if any of the following hold:
  - Buffer is shorter than 8 bytes (`truncatedHeader`).
  - `version != 0x01` (`unsupportedVersion`).
  - `reserved != 0x00` (`invalidReserved`).
  - `data_length > remainingBytes` (`truncatedBody`).
  - `screen_id` is not in the Screen IDs table (`unknownScreenId`).
  - Body length does not match the expected length for the screen
    (`bodyLengthMismatch`).
  - Flags bits 3..7 are set (`reservedFlagsSet`).

## Screen IDs

| ID | Constant | Name | Slice | Body type |
|---|---|---|---|---|
| `0x01` | `navigation`    | Navigation        | 6   | `nav_data_t` |
| `0x02` | `speedHeading`  | Speed + Heading   | 3   | TBD |
| `0x03` | `compass`       | Compass           | 4   | TBD |
| `0x04` | `weather`       | Weather           | 7   | TBD |
| `0x05` | `tripStats`     | Trip Stats        | 9   | TBD |
| `0x06` | `music`         | Music             | 8   | TBD |
| `0x07` | `leanAngle`     | Lean Angle        | 10  | TBD |
| `0x08` | `blitzer`       | Blitzer / Radar   | 14  | TBD |
| `0x09` | `incomingCall`  | Incoming Call     | 13  | TBD |
| `0x0A` | `fuelEstimate`  | Fuel Estimate     | 12  | TBD |
| `0x0B` | `altitude`      | Altitude Profile  | 15  | TBD |
| `0x0C` | `appointment`   | Next Appointment  | 11  | TBD |
| `0x0D` | `clock`         | Idle / Clock      | 2   | `clock_data_t` |

All other values are reserved and must be rejected by decoders.

## Flags bitfield

Bit 0 is the least significant.

| Bit | Constant | Meaning |
|---|---|---|
| 0 | `ALERT` | This payload is an alert overlay with priority — ESP32 interrupts the current screen and returns after `STALE` or a clear command. |
| 1 | `NIGHT_MODE` | Render in night palette (dim background, red-shift UI). |
| 2 | `STALE` | Data is stale — renderer shows a visual staleness indicator. |
| 3–7 | reserved | Must be `0`. |

## Screen body definitions

### `clock_data_t` (screen `0x0D`)

Body size: **12 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `unix_time` | `uint64` | Seconds since Unix epoch, UTC. |
| 8 | `tz_offset_minutes` | `int16` | Local timezone offset from UTC, in minutes. Range `-720..=840`. |
| 10 | `flags` | `uint8` | Bit 0: 24-hour format. Other bits reserved. |
| 11 | `reserved` | `uint8` | Must be `0x00`. |

### `nav_data_t` (screen `0x01`)

Body size: **56 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `lat_e7` | `int32` | Latitude × 10⁷. Range `-900000000..=900000000`. |
| 4 | `lng_e7` | `int32` | Longitude × 10⁷. Range `-1800000000..=1800000000`. |
| 8 | `speed_kmh_x10` | `uint16` | Speed × 10. Max 3000 (300.0 km/h). |
| 10 | `heading_deg_x10` | `uint16` | Heading × 10. Range `0..=3599`. |
| 12 | `distance_to_maneuver_m` | `uint16` | Metres to next maneuver. `0xFFFF` = unknown. |
| 14 | `maneuver_type` | `uint8` | See Maneuver Types below. |
| 15 | `reserved` | `uint8` | Must be `0x00`. |
| 16 | `street_name` | `char[32]` | UTF-8, zero-padded, null-terminated. |
| 48 | `eta_minutes` | `uint16` | Minutes to destination. `0xFFFF` = unknown. |
| 50 | `remaining_km_x10` | `uint16` | Remaining distance × 10. `0xFFFF` = unknown. |
| 52 | `reserved2` | `uint32` | Must be `0x00000000`. |

### Maneuver types

| ID | Name |
|---|---|
| `0x00` | `none` |
| `0x01` | `straight` |
| `0x02` | `slightLeft` |
| `0x03` | `left` |
| `0x04` | `sharpLeft` |
| `0x05` | `uTurnLeft` |
| `0x06` | `slightRight` |
| `0x07` | `right` |
| `0x08` | `sharpRight` |
| `0x09` | `uTurnRight` |
| `0x0A` | `roundaboutEnter` |
| `0x0B` | `roundaboutExit` |
| `0x0C` | `merge` |
| `0x0D` | `forkLeft` |
| `0x0E` | `forkRight` |
| `0x0F` | `arrive` |

Other screen body definitions are added by their respective slices and follow the
same pattern: fixed offsets, fixed size, explicit reserved bytes.

## Control commands

Defined in Slice 5 (#6). Placeholder.

## Status notifications

Defined in Slice 2 (#3). Placeholder.

## Golden fixtures

Shared binary fixtures for round-trip tests live in `protocol/fixtures/`. Each
fixture is a raw byte blob (`.bin`) accompanied by a `.json` description of its
decoded contents. The Swift `BLEProtocolTests` target and the C `test_ble_protocol`
Unity binary both load the same files and assert:

1. Decoding the blob produces exactly the values in the `.json`.
2. Re-encoding those values produces exactly the original bytes.

Any change to the wire format must ship with fixture updates in the same commit.
