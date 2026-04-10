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
| `0x03` | `compass`       | Compass           | 4   | `compass_data_t` |
| `0x04` | `weather`       | Weather           | 7   | `weather_data_t` |
| `0x05` | `tripStats`     | Trip Stats        | 9   | `trip_stats_data_t` |
| `0x06` | `music`         | Music             | 8   | TBD |
| `0x07` | `leanAngle`     | Lean Angle        | 10  | `lean_angle_data_t` |
| `0x08` | `blitzer`       | Blitzer / Radar   | 14  | `blitzer_data_t` |
| `0x09` | `incomingCall`  | Incoming Call     | 13  | `incoming_call_data_t` |
| `0x0A` | `fuelEstimate`  | Fuel Estimate     | 12  | `fuel_data_t` |
| `0x0B` | `altitude`      | Altitude Profile  | 15  | `altitude_profile_data_t` |
| `0x0C` | `appointment`   | Next Appointment  | 11  | `appointment_data_t` |
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

### `compass_data_t` (screen `0x03`)

Body size: **8 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `magnetic_heading_deg_x10` | `uint16` | Magnetic heading × 10. Range `0..=3599`. |
| 2 | `true_heading_deg_x10` | `uint16` | True heading × 10. Range `0..=3599`, or `0xFFFF` if the heading fix is unavailable (e.g. no GPS lock yet). |
| 4 | `heading_accuracy_deg_x10` | `uint16` | Reported heading accuracy × 10 in degrees. Range `0..=3599`. |
| 6 | `compass_flags` | `uint8` | Bit 0: `USE_TRUE_HEADING`. If set, the screen renders the true heading; otherwise magnetic. Bits 1..7 reserved, must be `0`. |
| 7 | `reserved` | `uint8` | Must be `0x00`. |

If `USE_TRUE_HEADING` is set but `true_heading_deg_x10 == 0xFFFF`, the renderer falls back to the magnetic reading and displays a `MAG` label instead of `TRU`.

### `lean_angle_data_t` (screen `0x07`)

Body size: **8 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `current_lean_deg_x10` | `int16` | Current lean × 10. Negative = left lean, positive = right lean. Range `-900..=900` (±90.0°). |
| 2 | `max_left_lean_deg_x10` | `uint16` | Max left lean magnitude × 10 (unsigned). Range `0..=900`. |
| 4 | `max_right_lean_deg_x10` | `uint16` | Max right lean magnitude × 10 (unsigned). Range `0..=900`. |
| 6 | `confidence_percent` | `uint8` | Renderer confidence in the calculation, `0..=100`. Drops when non-gravitational acceleration spikes (hard braking, bumps). |
| 7 | `reserved` | `uint8` | Must be `0x00`. |

The sign convention is locked in here so the iOS calculator, the C
codec, and the host-sim renderer all agree: a bike leaning *right*
produces a *positive* `current_lean_deg_x10`. The same convention is
documented in `LeanAngleCalculator.swift`.

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

### `trip_stats_data_t` (screen `0x05`)

Body size: **16 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `ride_time_seconds` | `uint32` | Total accumulated ride time, in seconds. Sum of positive `Δt` between consecutive samples (so scenario gaps do not inflate it). |
| 4 | `distance_meters` | `uint32` | Total accumulated distance, in metres (haversine between consecutive samples). |
| 8 | `average_speed_kmh_x10` | `uint16` | Average ground speed × 10. Range `0..=3000` (300.0 km/h). Computed as `distance_m / ride_time_s × 3.6 × 10` and clamped. |
| 10 | `max_speed_kmh_x10` | `uint16` | Maximum recorded ground speed × 10. Range `0..=3000`. |
| 12 | `ascent_meters` | `uint16` | Total positive elevation change, in metres. Altitude jitter under 1 m is ignored. |
| 14 | `descent_meters` | `uint16` | Total negative elevation change (magnitude), in metres. |

### `music_data_t` (screen `0x06`)

Body size: **86 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `music_flags` | `uint8` | Bit 0: `PLAYING`. Bits 1..7 reserved, must be `0`. |
| 1 | `reserved` | `uint8` | Must be `0x00`. |
| 2 | `position_seconds` | `uint16` | Current playback position. `0xFFFF` = unknown (e.g. live radio stream). |
| 4 | `duration_seconds` | `uint16` | Track duration. `0xFFFF` = unknown. |
| 6 | `title` | `char[32]` | UTF-8, zero-padded, null-terminated. ≤ 31 bytes. |
| 38 | `artist` | `char[24]` | UTF-8, zero-padded, null-terminated. ≤ 23 bytes. |
| 62 | `album` | `char[24]` | UTF-8, zero-padded, null-terminated. ≤ 23 bytes. |

See [platform-limits.md](platform-limits.md) for the iOS `MPNowPlayingInfoCenter`
restriction — Slice 8 ships a testable protocol seam but defers the system
framework wiring to a follow-up.

### `appointment_data_t` (screen `0x0C`)

Body size: **60 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `starts_in_minutes` | `int16` | Minutes until event start. Negative = already started. Range `-1440..=10080` (plus/minus 7 days). |
| 2 | `title` | `char[32]` | UTF-8, zero-padded, null-terminated. Must contain a terminator (len < 32). |
| 34 | `location` | `char[24]` | UTF-8, zero-padded, null-terminated. Must contain a terminator (len < 24). |
| 58 | `reserved` | `uint16` | Must be `0x0000`. |

### `fuel_data_t` (screen `0x0A`)

Body size: **8 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `tank_percent` | `uint8` | Estimated fuel remaining as percentage. Range `0..=100`. |
| 1 | `reserved` | `uint8` | Must be `0x00`. |
| 2 | `estimated_range_km` | `uint16` | Estimated remaining range in km. `0xFFFF` = unknown. |
| 4 | `consumption_ml_per_km` | `uint16` | Average fuel consumption in mL/km. `0xFFFF` = unknown. |
| 6 | `fuel_remaining_ml` | `uint16` | Estimated fuel remaining in mL. `0xFFFF` = unknown. |

The Scram 411 has no fuel sensor or OBD port. All values are computed from
manual fill logging: the rider records fill-ups and the app tracks distance
via GPS. If no full fills have been logged, consumption is unknown and all
uint16 fields are set to `0xFFFF`.

The `tank_percent` is derived from `fuel_remaining_ml / tank_capacity_ml * 100`
where `tank_capacity_ml` is a user-configurable constant (default 13 000 mL
for the Scram 411's 13 L tank).

### `altitude_profile_data_t` (screen `0x0B`)

Body size: **128 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `current_altitude_m` | `int16` | Current altitude in metres. Range `-500..=9000`. |
| 2 | `total_ascent_m` | `uint16` | Cumulative ascent in metres since ride start. |
| 4 | `total_descent_m` | `uint16` | Cumulative descent in metres since ride start. |
| 6 | `sample_count` | `uint8` | Number of valid samples in the `profile` array. Range `0..=60`. |
| 7 | `reserved` | `uint8` | Must be `0x00`. |
| 8 | `profile` | `int16[60]` | Altitude samples in metres, evenly spaced over the ride duration. Entries beyond `sample_count` must be `0x0000`. |

This is the largest screen payload (128-byte body, 136 bytes total with header).
The `profile` array is a downsampled elevation history — the iOS service bins
the full altitude trace into 60 evenly-spaced buckets (by averaging) so it fits
in a single BLE write. Each bucket holds the average altitude during that time
window. When fewer than 60 samples have been collected, `sample_count` reflects
the actual count and unused profile slots are zero-padded.

Ascent and descent totals are jitter-filtered (deltas under 1 m are discarded)
to suppress GPS noise, matching the `TripStatsAccumulator` behaviour.

### EventKit integration note (Slice 11)

The Slice 11 iOS code ships a `CalendarServiceClient` abstraction with a
`StaticCalendarServiceClient` for tests and an `EventKitCalendarClient` stub
that throws `notImplemented`. Wiring the real EventKit API requires an
`NSCalendarsFullAccessUsageDescription` key in Info.plist (iOS 17+) and a
runtime `EKEventStore.requestFullAccessToEvents()` call, both of which are
deferred to a follow-up PR that will swap the stub without touching the wire
format.

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

### `weather_data_t` (screen `0x04`)

Body size: **28 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `condition` | `uint8` | See Weather conditions below. |
| 1 | `reserved` | `uint8` | Must be `0x00`. |
| 2 | `temperature_celsius_x10` | `int16` | Current temperature × 10. Range `-500..=600` (-50°C..60°C). |
| 4 | `high_celsius_x10` | `int16` | Daily high × 10. Same range. |
| 6 | `low_celsius_x10` | `int16` | Daily low × 10. Same range. |
| 8 | `location_name` | `char[20]` | UTF-8, zero-padded, null-terminated. Must contain a terminator (len < 20). |

### Weather conditions

| ID | Name |
|---|---|
| `0x00` | `clear` |
| `0x01` | `cloudy` |
| `0x02` | `rain` |
| `0x03` | `snow` |
| `0x04` | `fog` |
| `0x05` | `thunderstorm` |

Unknown values are rejected with `valueOutOfRange` (field `weather.condition`).

### WeatherKit integration note (Slice 7)

The Slice 7 iOS code ships a `WeatherServiceClient` abstraction with a
`StaticWeatherServiceClient` for tests and a `WeatherKitClient` stub that
throws `notImplemented`. Wiring the real WeatherKit REST API requires an
Apple Developer account with the WeatherKit capability and a signed `.p8`
key — both infrastructure concerns outside the scope of the dashboard
protocol work. A follow-up PR will replace the stub without touching the
wire format.

### `incoming_call_data_t` (screen `0x09`)

Body size: **32 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `call_state` | `uint8` | `0x00` = incoming, `0x01` = connected, `0x02` = ended. Unknown values are rejected with `valueOutOfRange`. |
| 1 | `reserved` | `uint8` | Must be `0x00`. |
| 2 | `caller_handle` | `char[30]` | UTF-8, zero-padded, null-terminated. Must contain a terminator (len < 30). On iOS the carrier identity is NOT available to third-party apps, so this field carries an app-level contact alias or "unknown". See [platform-limits.md](./platform-limits.md). |

#### ALERT flag interaction (Slice 13)

The `ALERT` header flag (bit 0 in the `flags` byte -- see
[Flags bitfield](#flags-bitfield)) has special meaning for incoming call
payloads:

- When `call_state` is `incoming` (`0x00`) or `connected` (`0x01`), the
  iOS encoder **must set** the `ALERT` flag. This signals the ESP32 screen
  FSM to treat the payload as a priority overlay: it interrupts the
  current screen and returns to the previous screen after the call clears.
- When `call_state` is `ended` (`0x02`), the iOS encoder **must clear**
  the `ALERT` flag. The ESP32 FSM uses this as the signal to dismiss the
  overlay and restore the previous screen.

The ALERT flag lives in the **header**, not in the body. The body
`call_state` field and the header `flags` byte must be consistent --
decoders may reject a payload where `call_state == ended` but `ALERT` is
set, or where `call_state == incoming` but `ALERT` is clear, as a
protocol-level warning (though the current codecs do not enforce this
for forward compatibility).

### `blitzer_data_t` (screen `0x08`)

Body size: **8 bytes**

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | `distance_meters` | `uint16` | Distance to the nearest camera in metres. |
| 2 | `speed_limit_kmh` | `uint16` | Speed limit at the camera in km/h. `0xFFFF` = unknown. |
| 4 | `current_speed_kmh_x10` | `uint16` | Current GPS speed × 10. |
| 6 | `camera_type` | `uint8` | See Camera types below. |
| 7 | `reserved` | `uint8` | Must be `0x00`. |

### Camera types

| ID | Name |
|---|---|
| `0x00` | `fixed` |
| `0x01` | `mobile` |
| `0x02` | `redLight` |
| `0x03` | `section` |
| `0x04` | `unknown` |

Unknown values are rejected with `valueOutOfRange` (field `blitzer.camera_type`).

#### ALERT flag interaction (Slice 14)

The `ALERT` header flag (bit 0) is used to control the priority overlay
lifecycle, following the same pattern as `incoming_call_data_t` (Slice 13):

- When the rider is within the configured alert radius of a speed camera,
  the iOS encoder **must set** the `ALERT` flag. The ESP32 screen FSM
  treats this as a priority overlay that interrupts the current screen.
- When no camera is in range (and the previous emission had `ALERT` set),
  the iOS encoder emits one final payload with `ALERT` **cleared**. The
  ESP32 uses this to dismiss the overlay and restore the previous screen.

The iOS `BlitzerAlertService` controls the enter/exit logic. The default
alert radius is 500 metres, configurable via `BlitzerSettings`.

#### Swiss legal status

Passive radar-warning apps that display the positions of fixed speed
cameras from open databases (e.g. OpenStreetMap `highway=speed_camera`
nodes) were ruled legal in Switzerland by the Bundesgericht in 2024. The
ruling distinguishes passive lookup of known positions from active radar
detection, which remains illegal under SVG Art. 98a. This feature relies
solely on the passive lookup model. The camera database is loaded from a
local JSON file on the iPhone; no active detection hardware is involved.

Other screen body definitions are added by their respective slices and follow the
same pattern: fixed offsets, fixed size, explicit reserved bytes.

## Control commands

Defined in Slice 5 (#6). The `control` characteristic accepts fixed-size
4-byte writes from the iOS app. Every command shares the same envelope:

```
 0       1       2       3
+-------+-------+-------+-------+
|version|  cmd  |   value...    |
+-------+-------+-------+-------+
```

| Field | Bytes | Notes |
|---|---|---|
| `version` | 1 | `0x01`, same as the screen-data version. |
| `command` | 1 | See command table below. |
| `value`   | 2 | Command-specific. Bytes not used by a given command must be `0x00` on encode and decoders must reject non-zero. |

The total encoded size is **always 4 bytes**. Picking a fixed size keeps the
codec boring and the wire-format diff between Swift and C trivially
verifiable against the golden fixtures under `protocol/fixtures/control/`.

### Command table

| ID | Name | Value bytes | Body | Meaning |
|---|---|---|---|---|
| `0x01` | `setActiveScreen`   | 1 | byte 0: `screen_id` (see [Screen IDs](#screen-ids)); byte 1: `0x00` | Switch the active persistent screen. |
| `0x02` | `setBrightness`     | 1 | byte 0: brightness `0..100`; byte 1: `0x00` | Set panel brightness as a percentage. |
| `0x03` | `sleep`             | 0 | both bytes `0x00` | Dim and enter sleep state. |
| `0x04` | `wake`              | 0 | both bytes `0x00` | Wake from sleep, return to the previously selected screen. |
| `0x05` | `clearAlertOverlay` | 0 | both bytes `0x00` | Clear any active alert overlay and return to the previously selected screen. |

### Decoder rules

Decoders must fail with a clear error if any of the following hold:

- Buffer is shorter than 4 bytes (`truncatedHeader`).
- `version != 0x01` (`unsupportedVersion`).
- `command` is not in the table above (`unknownCommand`).
- The unused trailing value byte for a command is non-zero (`invalidReserved`).
- `setActiveScreen.screen_id` is not in the [Screen IDs](#screen-ids) table
  (`unknownScreenId`).
- `setBrightness` value > 100 (`invalidCommandValue`).

## GATT server implementation

The ESP32 GATT server lives in
`hardware/firmware/components/ble_server/`. It uses the NimBLE static
GATT table approach (`ble_gatt_svc_def` arrays) with three
characteristics matching the UUIDs above. Write callbacks in
`ble_server.c` flatten the NimBLE mbuf and forward raw bytes to the
pure-C dispatch layer in `ble_server_handlers.c`, which routes them
through `ble_protocol`, `screen_fsm`, and `ble_reconnect`. The handler
file has zero ESP-IDF dependencies and is host-tested via Unity (see
`hardware/firmware/test/host/test_ble_server_handlers.c`).

## Status notifications

Defined in Slice 2 (#3). Placeholder.

### Staleness flag and the last-known-payload cache

The `STALE` flag (bit 2 in the screen header — see
[Flags bitfield](#flags-bitfield)) is raised by the ESP32 renderer
when the last-known payload for the current screen is older than a configured
threshold. It is **not** set by the iOS side on the wire; the ESP32 owns it
because the ESP32 is the side that keeps drawing during BLE outages.

Slice 17 adds two matching caches that cooperate with this flag:

- **iOS** — `BLECentralClient.LastKnownPayloadCache` stores the last body
  successfully written per `ScreenID`. During a reconnect loop the UI can ask
  the cache for a snapshot and render a "last known" state instead of a blank
  widget. The cache is clock-agnostic; callers pass a timestamp on every
  mutation so tests drive it with a `VirtualClock`.
- **ESP32** — the `ble_reconnect` component exposes an equivalent
  `ble_payload_cache_t` (14 slots, one per screen id, 64-byte bodies) that the
  firmware updates on every successful write and queries from the render loop.
  When `ble_payload_cache_is_stale()` returns `true` for the active screen,
  the renderer sets the `STALE` flag on whatever frame it draws from the
  cached body.

The staleness threshold is a property of the renderer, not the wire format —
both sides default to 2 seconds and can be tuned per screen without a
protocol bump. See [background-ble.md](./background-ble.md) for the full
reconnect lifecycle.

## Golden fixtures

Shared binary fixtures for round-trip tests live in `protocol/fixtures/`. Each
fixture is a raw byte blob (`.bin`) accompanied by a `.json` description of its
decoded contents. The Swift `BLEProtocolTests` target and the C `test_ble_protocol`
Unity binary both load the same files and assert:

1. Decoding the blob produces exactly the values in the `.json`.
2. Re-encoding those values produces exactly the original bytes.

Any change to the wire format must ship with fixture updates in the same commit.
