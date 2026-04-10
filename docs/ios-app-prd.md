# PRD: ScramScreen iOS Companion App

**Owner:** Alejandro
**Status:** Implementation
**Parent:** [ScramScreen PRD](prd.md)
**BLE Protocol:** [ble-protocol.md](ble-protocol.md)

This document defines the iOS app's responsibilities, data production logic, and
implementation decisions. The ESP32 is a dumb display with local screen switching —
all data fetching, computation, and routing lives on the iPhone.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                    iOS App                            │
│                                                      │
│  ┌──────────────┐   ┌─────────────────────────────┐  │
│  │  RideSession  │──▶│  Service Layer (13 services) │  │
│  │  (actor)      │   │  Each produces AsyncStream   │  │
│  │               │   │  of encoded BLE payloads     │  │
│  └──────┬───────┘   └──────────┬──────────────────┘  │
│         │                      │                      │
│         ▼                      ▼                      │
│  ┌──────────────┐   ┌─────────────────────────────┐  │
│  │  Payload      │──▶│  BLECentralClient            │  │
│  │  Scheduler    │   │  (CoreBluetooth)             │  │
│  └──────────────┘   └──────────┬──────────────────┘  │
└─────────────────────────────────┼────────────────────┘
                                  │ BLE GATT
                                  ▼
                        ┌──────────────────┐
                        │  ESP32 Firmware   │
                        │  - Caches latest  │
                        │    payload/screen │
                        │  - Button cycles  │
                        │    screens locally│
                        │  - Renders LVGL   │
                        └──────────────────┘
```

### Key Principle: Firmware-Side Screen Switching

The firmware caches the latest BLE payload for every enabled screen. A handlebar
button wired to ESP32 GPIO cycles through screens locally — no BLE round-trip
needed. iOS stays informed via `SCREEN_CHANGED` status notifications.

---

## Ride Session Lifecycle

### Boot Sequence

1. Bike ignition on → ESP32 boots → displays **ScramScreen logo** (hardcoded in firmware)
2. iOS app detects ESP32 via BLE → connects
3. iOS sends `setScreenOrder` control command (ordered list of enabled screen IDs)
4. iOS immediately sends a fresh payload for the first screen in the list
5. Firmware switches from logo to first screen
6. `RideSession` starts all data services

### During Ride

- All services run concurrently, producing payloads via `AsyncStream<Data>`
- `RideSession` actor consumes all streams and funnels payloads to BLE
- Payload scheduler throttles: active screen at full rate, background screens reduced
- Firmware caches latest payload per screen ID for instant button-press switching
- Firmware notifies iOS of screen changes via `SCREEN_CHANGED` on `status` characteristic

### Ride End

- Bike ignition off → ESP32 powers down → BLE disconnects
- iOS detects disconnect → `RideSession` stops all services
- Trip summary saved to persistent storage (see Trip History)
- GPS odometer value persisted (see Fuel Tracking)

---

## Protocol Additions Required

These extend the existing [BLE protocol](ble-protocol.md):

### Control Commands (Phone → ESP32)

| Command | Payload | Description |
|---|---|---|
| `setScreenOrder` | `uint8 count` + `uint8[] screen_ids` | Ordered list of enabled screens for button cycling |

### Status Messages (ESP32 → Phone)

| Message | Payload | Description |
|---|---|---|
| `SCREEN_CHANGED` | `uint8 screen_id` | Firmware notifies iOS which screen is now displayed |
| `BUTTON_PRESS` | `uint8 action` | Reserved for future button actions beyond cycling |

---

## Payload Scheduling

BLE 4.2 supports ~10-20 writes/second on a single characteristic. With up to
6 services producing at 1 Hz simultaneously, bandwidth must be managed.

### Rules

| Screen relationship | Update rate |
|---|---|
| Currently displayed screen | Full rate (1 Hz for location-based, on-change for others) |
| Background screens | Reduced rate (~every 5 seconds) |
| On `SCREEN_CHANGED` from firmware | Immediately send fresh payload for new screen, promote to full rate |

### Update Frequencies by Screen

| Screen | Trigger | Full Rate | Background Rate |
|---|---|---|---|
| Speed + Heading | Location sample | 1 Hz | 5s |
| Compass | Location sample | 1 Hz | 5s |
| Navigation | Location sample | 1 Hz | 5s |
| Lean Angle | Motion sample | 1 Hz | 5s |
| Altitude Profile | Location sample | 1 Hz | 5s |
| Trip Stats | Location sample | 1 Hz | 5s |
| Clock | Timer | 30s | 30s |
| Weather | Provider change or timer | 60s | 60s |
| Calendar | Provider change or timer | 60s | 60s |
| Fuel Estimate | On fill entry or timer | 60s | 60s |
| Music | Now-playing change | On change | 5s |
| Incoming Call | Call state change | Immediate | N/A (alert) |
| Speed Camera | Proximity threshold | Immediate | N/A (alert) |

---

## Screen Switching

### Handlebar Button (Primary)

- Physical button wired to ESP32 GPIO
- Firmware detects press, advances to next screen in the ordered list (wraps around)
- Firmware renders from cached payload — no iOS round-trip latency
- Firmware sends `SCREEN_CHANGED` status notification to iOS

### No Auto-Rotation

There is no timer-based screen cycling. The rider controls which screen is visible
via the handlebar button. Showing the wrong screen at the wrong time (e.g., lean
angle instead of a turn instruction) is a safety risk.

### No Auto-Switch on Navigation

Navigation does not automatically take over the display when a route starts. The
rider chooses which screen to view. Navigation data is always being sent in the
background so it's ready when the rider switches to it.

---

## Alert System

Alerts interrupt the current screen via the firmware's `ALERT_OVERLAY` state.
Only alerts use this mechanism — regular screens never auto-switch.

### Priority (highest first)

| Priority | Alert | Behavior |
|---|---|---|
| 1 | **Incoming Call** | Full overlay on any screen. Dismissed when call ends (answered, declined, or missed). |
| 2 | **Speed Camera** | Full overlay on non-navigation screens. During navigation: sets `ALERT` flag in payload header instead (firmware renders subtle indicator without hiding turn instructions). |

### Rules

- Only one overlay at a time; higher priority replaces lower
- When alert clears, firmware returns to the previously displayed screen
- Alert payloads are sent immediately regardless of scheduling rules

---

## Data Services

### 1. Clock

**Service:** `ClockService` (to be created)
**Input:** System clock
**Output:** `ClockData` payloads every 30 seconds
**Logic:** Encode current date, time, timezone, 24h/12h preference. No RTC on
firmware — iOS is the sole time source.

Clock is a regular screen in the ordered list, not a boot/home screen.

### 2. Speed + Heading

**Service:** `SpeedHeadingService` (exists)
**Input:** `RealLocationProvider` → `CLLocation`
**Output:** `SpeedHeadingData` payloads at 1 Hz
**Logic:** GPS speed (clamped to 300 km/h), GPS course (direction of travel),
altitude. Temperature hardcoded to 0 until a source is identified.

### 3. Compass

**Service:** Uses `SpeedHeadingService` data (no separate service)
**Input:** `CLLocation.course` (GPS course over ground)
**Output:** `CompassData` payloads at 1 Hz
**Decision:** GPS course is sufficient. No magnetic heading (`CLHeading`) needed.
Compass data is only meaningful while moving — at standstill, heading holds last
known value.

### 4. Navigation

**Service:** `NavigationService` (exists)
**Input:** `MKDirectionsRouteEngine` + `RealLocationProvider`
**Output:** `NavData` payloads at 1 Hz while routing

#### Starting Navigation

- User enters destination in the app via a search field before riding
- Uses `MKLocalSearchCompleter` for autocomplete
- Tap "Los" to calculate route via `MKDirections` and start tracking

#### Off-Route Handling

- `RouteTracker` detects position >100m from polyline for >10 seconds
- Triggers automatic reroute: new `MKDirections` request from current position to
  same destination
- Seamless — rider sees updated turn instructions without interaction

#### Arrival

- When `RouteTracker` detects arrival at destination
- Navigation session ends silently
- No arrival splash screen — display continues showing current screen
- `NavigationService` stops producing payloads

### 5. Weather

**Service:** `WeatherService` (exists)
**Input:** `RealWeatherProvider` → WeatherKit API
**Output:** `WeatherData` payloads on change or every 60 seconds
**Logic:** Maps WeatherKit conditions to wire enum, clamps temperatures to
-50..60 range, truncates location name to 19 UTF-8 bytes.

### 6. Trip Stats

**Service:** `TripStatsService` (exists)
**Input:** Location samples from `RealLocationProvider`
**Output:** `TripStatsData` payloads at 1 Hz
**Logic:** `TripStatsAccumulator` tracks elapsed time, distance, avg/max speed,
elevation gain. Resets to zero on each new ride (BLE connect).

#### Trip History Persistence

On ride end (BLE disconnect), save a `TripSummary` to persistent storage:

```swift
struct TripSummary: Codable {
    let date: Date
    let duration: TimeInterval
    let distanceKm: Double
    let avgSpeedKmh: Double
    let maxSpeedKmh: Double
    let elevationGainM: Double
}
```

Stored as JSON array in UserDefaults. Displayed in the **Fahrten** tab.

### 7. Music

**Service:** `MusicService` (exists)
**Input:** `MediaPlayerNowPlayingClient` → `MPNowPlayingInfoCenter`
**Output:** `MusicData` payloads on change
**Logic:** Reads title, artist, duration, playback position, playing state.
Handles nil fields gracefully (Spotify provides all fields reliably, YouTube Music
may omit some). Title truncated to 30 UTF-8 bytes, artist to 25.

### 8. Lean Angle

**Service:** `LeanAngleService` (exists)
**Input:** `RealMotionProvider` → `CMMotionManager`
**Output:** `LeanAngleData` payloads at 1 Hz

#### Auto-Calibration (Phone in Pocket)

The phone orientation is unknown and changes every ride. Calibration is automatic:

1. On ride start, `LeanAngleCalculator` reports `confidence = 0%` (firmware shows
   "Kalibrierung..." state)
2. Service monitors GPS: waits for speed >20 km/h with stable heading (~5 seconds
   of straight riding)
3. Captures average gravity vector as the "upright" reference
4. Starts reporting real lean angles with increasing confidence
5. Recalibrates every ~10 minutes to account for phone shifting in pocket

**Sign convention:** Negative = left lean, positive = right lean. Range: ±90 degrees.

#### Background Mode

Lean angle sampling drops from device default to 5 Hz when app is backgrounded to
reduce CPU usage and avoid iOS throttling.

### 9. Calendar

**Service:** `CalendarService` (exists)
**Input:** `EventKitCalendarClient` → EventKit
**Output:** `AppointmentData` payloads on change or every 60 seconds

#### Calendar Selection

- User selects which calendars to include in **Mehr** tab under "Kalender" section
- UI: list of all EventKit calendars with color dots and toggles
- Persisted to UserDefaults (calendar identifiers)
- Default: all calendars enabled
- List refreshes when Mehr tab appears (handles calendars added/removed externally)
- New calendars default to enabled; deleted calendars removed from selection

### 10. Fuel Estimate

**Service:** `FuelService` (exists)
**Input:** Manual fill entries + GPS odometer
**Output:** `FuelData` payloads on change or every 60 seconds

#### GPS Odometer

- Persistent cumulative distance counter (UserDefaults)
- Incremented by `CLLocation` distance deltas during rides
- Never resets — survives across trips and app restarts
- Separate from `TripStatsAccumulator` (which resets per ride)

#### Fill Entry (Tank Tab)

The **Tank** tab (currently placeholder) provides:

- **Fill entry form:**
  - Liters filled (required, numeric input)
  - "Tank voll" toggle (optional, default off)
- **Fill history list** with date, liters, calculated consumption
- **Current estimates:** remaining range, avg consumption

#### Consumption Calculation

- When "Tank voll" is toggled on: recalibrate.
  `consumption = total_liters_since_last_full / distance_since_last_full`
- Between full fills: running total.
  `estimated_remaining = (tank_capacity - estimated_consumed) / avg_consumption_rate`
- Tank capacity: user-configurable in **Mehr** settings (default 15L for Scram 411)
- Partial fills add to `total_liters_since_last_full` counter without recalibrating

#### Data Persistence

- `FuelLogStore` persists fill history to UserDefaults as JSON (exists)
- GPS odometer value persisted separately

### 11. Speed Camera (Blitzer)

**Service:** `BlitzerAlertService` (exists)
**Input:** Location samples + `SpeedCameraDatabase`
**Output:** `BlitzerData` payloads when camera is within alert radius

#### Database

- **Scope:** Switzerland only
- **Source:** OpenStreetMap, `highway=speed_camera` tag
- **Format:** Bundled SQLite file in app bundle
- **Updates:** New dataset shipped with each app release (build-time Overpass query)
- **Legal:** Permitted in Switzerland (Bundesgericht ruling 2024)

#### Alert Behavior

- Default alert radius: 500m (configurable via `BlitzerSettings`)
- On non-navigation screen: full alert overlay
- On navigation screen: `ALERT` flag set in nav payload header (subtle indicator,
  no overlay — turn instructions remain visible)

### 12. Incoming Call

**Service:** `CallAlertService` (exists)
**Input:** `RealCallObserver` → `CXCallObserver`
**Output:** `IncomingCallData` payloads on call state change

- Highest priority alert — always overlays, on any screen
- Displays caller name
- Dismissed automatically when call ends (answered, declined, or missed)

### 13. Altitude Profile

**Service:** `AltitudeService` (exists)
**Input:** Location samples → `CLLocation.altitude`
**Output:** `AltitudeProfileData` payloads at 1 Hz
**Logic:** `ElevationHistoryBuffer` stores last 60 elevation samples as ring buffer.
Tracks cumulative ascent and descent.

---

## Night Mode

### Automatic (Default)

- `NightModeService` uses `SunriseSunsetCalculator` with current GPS position
- After sunset: sets `NIGHT_MODE` flag in BLE payload headers
- Before sunrise: same
- Firmware adjusts color palette (dim amber) and brightness

### Manual Override

Three-way toggle in **Mehr** tab:

| Setting | Behavior |
|---|---|
| **Automatisch** (default) | Sunrise/sunset calculation |
| **Tag** | Always day mode |
| **Nacht** | Always night mode |

Persisted to UserDefaults.

---

## Background Execution

The app must keep running while the phone is in the rider's pocket.

### Background Modes (Info.plist)

- `location` — keeps the app alive via continuous location updates
- `bluetooth-central` — allows BLE writes while backgrounded

### Strategy

- `RealLocationProvider` sets `allowsBackgroundLocationUpdates = true` with
  `kCLLocationAccuracyBestForNavigation` — this is the primary keep-alive mechanism
- BLE writes continue normally in background
- `CMMotionManager` sampling drops to 5 Hz in background (lean angle)
- `beginBackgroundTask` as safety net during short state transitions

### Power Considerations

- All services are only active during a ride (BLE connected)
- When the bike is off and BLE is disconnected, no background activity

---

## OTA Firmware Updates

### Source

- Firmware binaries hosted on **GitHub Releases**
- Tag format: `fw-vX.Y.Z` (semver)
- ESP32 reports current firmware version via `status` characteristic on connect

### Check Frequency

- App checks GitHub Releases API on launch
- Cached for 24 hours (at most one check per day)
- Compares latest release version against ESP32-reported version

### Update Flow

1. New version detected → badge shown in **Mehr** tab next to firmware version
2. Rider taps "Update verfügbar" → confirmation dialog
3. iOS downloads `.bin` from GitHub Release asset
4. BLE OTA transfer: chunked write to ESP32 OTA partition
5. ESP32 verifies SHA256, writes to OTA partition, reboots
6. On boot, firmware validates new image; rolls back on failure

---

## App Tabs

### Home

**Status:** Implemented
- Connection status pill (scanning/connecting/connected/reconnecting/disconnected)
- Pair/connect/disconnect controls
- Quick stats (brightness, mode, firmware version)
- Navigation destination search field + "Los" button (to be added)
- Debug tools in DEBUG builds (ride simulator, screen picker)

### Screens

**Status:** Implemented
- Carousel preview of all 13 screen types (290x290 round mockups)
- Enable/disable toggle per screen
- Drag-to-reorder in sort sheet
- Order and enabled state persisted via `ScreenPreferences`
- Order synced to firmware via `setScreenOrder` on connect

### Fahrten (Trip History)

**Status:** Placeholder → to be implemented
- List of past ride summaries (date, duration, distance, avg/max speed, elevation)
- Saved on ride end (BLE disconnect)
- Stored as JSON array in UserDefaults
- Simple chronological list, newest first

### Tank (Fuel)

**Status:** Placeholder → to be implemented
- **Fill entry form:** liters (numeric), "Tank voll" toggle
- **Fill history:** list of past fills with date, liters, calculated consumption
- **Current estimates:** remaining range, avg consumption rate (km/L)
- **Tank capacity** configurable in Mehr settings (default 15L)

### Mehr (Settings)

**Status:** Implemented, needs additions
- **Device:** Paired device, firmware version, unpair, OTA update badge
- **Display:** Brightness slider (10-100%)
- **Nachtmodus:** Three-way toggle (Automatisch / Tag / Nacht) — to be added
- **Einheiten:** Speed (km/h / mph), Temperature (C / F)
- **Kalender:** Calendar selection with toggles — to be added
- **Tank:** Tank capacity setting (default 15L) — to be added
- **Blitzer:** Alert radius setting (default 500m)
- **Hinweise:** Alert sound toggle
- **Info:** App version, protocol version, licenses, feedback

---

## Missing Components (To Be Implemented)

### New Code

| Component | Package | Description |
|---|---|---|
| `RideSession` | ScramCore | Actor that orchestrates all services, manages lifecycle, funnels payloads to BLE |
| `PayloadScheduler` | ScramCore | Throttles background screen updates, promotes active screen to full rate |
| `ClockService` | ScramCore | Encodes current time as `ClockData` every 30 seconds |
| `CompassService` | ScramCore | Encodes GPS course as `CompassData` at 1 Hz (thin wrapper over location data) |
| `GPSOdometer` | ScramCore | Persistent cumulative distance counter for fuel calculations |
| `TripSummary` | ScramCore | Codable struct + persistence for ride history |
| `TripHistoryStore` | ScramCore | Save/load trip summaries from UserDefaults |
| `NavigationSearchView` | App | Destination search field with `MKLocalSearchCompleter` |
| `FahrtenView` | App | Trip history list view (replaces placeholder) |
| `TankView` | App | Fuel fill entry + history + estimates (replaces placeholder) |
| `CalendarSettingsView` | App | Calendar selection toggles for Mehr tab |
| `NightModeSettingsView` | App | Three-way night mode toggle for Mehr tab |
| `OTAUpdateView` | App | Firmware update flow UI in Mehr tab |
| `GitHubReleaseChecker` | ScramCore | Checks GitHub Releases API for new firmware versions |
| Lean angle auto-calibration | ScramCore | Straight-riding detection + gravity vector capture in `LeanAngleCalculator` |
| Off-route detection + reroute | ScramCore | Distance-from-polyline check in `RouteTracker`, auto-reroute in `NavigationService` |

### Protocol Extensions

| Addition | Characteristic | Direction |
|---|---|---|
| `setScreenOrder` command | `control` | Phone → ESP32 |
| `SCREEN_CHANGED` notification | `status` | ESP32 → Phone |

### Firmware Changes

| Change | Description |
|---|---|
| Payload cache | `latest_payload[13]` array — store most recent payload per screen ID |
| Screen order storage | Receive and store ordered screen list from `setScreenOrder` |
| Button handler | GPIO interrupt → advance screen index → render from cache → notify iOS |
| Status notifications | Send `SCREEN_CHANGED` on button press |

---

## Non-Goals

- No auto-sleep / auto-wake. Display stays on while bike is powered.
- No touch interaction (rider wears gloves).
- No standalone GPS on the ESP32.
- No Android support.
- No server infrastructure (except GitHub Releases for OTA).
- No magnetic compass (GPS course is sufficient).
- No multi-country speed camera database (Switzerland only for MVP).
- No timer-based screen auto-rotation.
- No auto-switch to navigation screen (rider controls via button).

---

## Success Criteria

1. `RideSession` survives 8+ hour ride without crash or memory leak
2. Screen data stays fresh — active screen payload age never exceeds 2 seconds
3. Background screen cache age never exceeds 10 seconds
4. BLE reconnects within 5 seconds, `RideSession` resumes all services
5. Lean angle calibrates within first 30 seconds of riding
6. Navigation reroutes within 15 seconds of going off-route
7. Trip summary is persisted on every ride end, even if app is backgrounded
8. Fuel range estimate is within 15% of actual range after 3+ fill-to-full cycles
9. OTA update completes successfully over BLE
