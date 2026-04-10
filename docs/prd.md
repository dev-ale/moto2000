# PRD: ScramScreen — Custom Round Motorcycle Display

## Overview

**ScramScreen** is a custom-built, waterproof, round AMOLED display that replaces the stock Royal Enfield Tripper Navigation pod on a Scram 411. It connects via BLE to an iOS companion app, turning the locked-down OEM navigation puck into a fully programmable motorcycle dashboard.

**Owner:** Alejandro
**Status:** iOS app implemented, firmware rendering complete, hardware integration next
**Target:** Personal use (single unit), open-source potential
**iOS implementation details:** [ios-app-prd.md](ios-app-prd.md)

---

## Problem Statement

The Royal Enfield Tripper Pod is locked to the proprietary RE app with limited functionality (Google Maps turn-by-turn only). It cannot display custom data, use alternative navigation providers, or integrate with external systems. No public reverse-engineering of the Tripper BLE protocol exists, making a custom firmware flash impractical. The solution is a full hardware replacement using the existing handlebar mount.

---

## Goals

1. Replace the Tripper Pod internals with a custom ESP32-S3 + AMOLED round display
2. Maintain the OEM look and waterproof integrity
3. Display real-time data from iPhone over BLE (navigation, speed, notifications, etc.)
4. Support multiple screen modes switchable from the phone
5. Keep the ESP32 firmware as a "dumb display" — all logic lives on the iPhone

## Non-Goals

- Standalone GPS on the display (iPhone provides all location data)
- Touch interaction while riding (gloves make this impractical)
- OBD/ECU integration (Scram 411 has no OBD port)
- Android support (iOS only, CoreBluetooth)
- Mass production or commercial sale

---

## Hardware

### Components

| Part | Spec | Est. Price |
|---|---|---|
| Waveshare ESP32-S3 1.75" AMOLED Round Display | 466×466px, QSPI, BLE 5.0 + WiFi, LX7 dual-core | ~CHF 25 |
| Mini buck converter | 12V → 5V (MP1584 or similar) | ~CHF 3 |
| IP67 cable gland | PG7, for power wire entry | ~CHF 2 |
| Silicone gasket / O-ring | Seal for housing | ~CHF 2 |
| Housing | Reuse Tripper Pod shell or 3D-print (PETG) + acrylic lens | ~CHF 0-10 |

**Total BOM: ~CHF 35-40**

### Power

- Source: Bike 12V from ignition-switched accessory line
- Buck converter steps down to 5V USB input on ESP32 board
- ESP32 draws ~120-200mA with AMOLED active
- Display auto-off when ignition is cut (no battery, no standby drain)

### Waterproofing Strategy

1. **Option A — Reuse Tripper Pod shell:** Gut the OEM electronics, fit ESP32 board inside, re-seal with original gaskets + silicone sealant (Dirko). Single cable gland for 12V power wire.
2. **Option B — Custom enclosure:** 3D-print PETG housing with clear acrylic or polycarbonate lens. O-ring groove in print. Cable gland for power. Conformal coating (Plastik 70) on PCB as secondary protection.

### Mounting

- Reuse existing Tripper Pod handlebar clamp bracket on the Scram 411
- If custom housing: design mount interface to match OEM clamp bolt pattern

### Pre-Build Step

- [ ] Remove Tripper Pod from bike
- [ ] Measure internal cavity diameter, depth, and mounting bolt pattern
- [ ] Confirm Waveshare 1.75" board fits (module ~44.5mm active area)
- [ ] Photograph internals for reference

---

## Screens

### Primary (riding)

| # | Screen | Data Source | Description |
|---|---|---|---|
| 1 | **Navigation** | iPhone (CLLocationManager + MapKit/nav provider) | Turn arrow, distance to next maneuver, street name, ETA, remaining distance |
| 2 | **Speed + Heading** | iPhone (CLLocation.speed, course) | Current GPS speed, compass heading, elevation, temperature |
| 3 | **Compass** | iPhone (CLLocation.course — GPS course, not magnetic) | Full compass rose with heading indicator |

### Secondary (glanceable info)

| # | Screen | Data Source | Description |
|---|---|---|---|
| 4 | **Weather** | iPhone (WeatherKit API or OpenWeather) | Current temp, condition icon, high/low, location |
| 5 | **Trip Stats** | iPhone (accumulated CLLocation data) | Ride time, distance, avg speed, max speed, elevation gain |
| 6 | **Music** | iPhone (MPNowPlayingInfoCenter) | Track title, artist, album art placeholder, progress bar |
| 7 | **Lean Angle** | iPhone (CMMotionManager accelerometer) | Real-time lean gauge, current angle, max L/R |

### Alerts (auto-triggered, overlay)

| # | Screen | Data Source | Description |
|---|---|---|---|
| 8 | **Radar / Blitzer** | iPhone (POIbase dataset or community DB vs GPS position) | Distance to camera, speed limit, current speed, camera type |
| 9 | **Incoming Call** | iPhone (CallKit / CXCallObserver) | Caller name/initial, accept/reject indicators |
| 10 | **Fuel Estimate** | iPhone (manual fill logging → calculated range) | Tank %, estimated range, consumption, fuel remaining |

### Passive (stationary / idle)

| # | Screen | Data Source | Description |
|---|---|---|---|
| 11 | **Altitude Profile** | iPhone (route elevation data from nav) | Elevation graph with current position marker, ascent/descent totals |
| 12 | **Next Appointment** | iPhone (EventKit / Calendar) | Next 1-2 calendar events, time until, location |
| 13 | **Idle / Clock** | iPhone (system clock, sent every 30s) | Date, time, timezone — no RTC on ESP32, iOS is sole time source |

### Screen Switching Logic

- **Handlebar button:** Physical button wired to ESP32 GPIO is the primary screen-cycling mechanism. Firmware stores the ordered list of enabled screens (via `setScreenOrder` command from iOS) and cycles through them locally using cached payloads — no BLE round-trip needed. iOS is notified of changes via `SCREEN_CHANGED` status notifications.
- **No auto-rotation:** The rider controls which screen is visible. No timer-based cycling (safety risk — showing wrong screen at wrong time).
- **No auto-switch on navigation:** Navigation does not take over the display when a route starts. The rider switches to it manually.
- **Alerts:** Incoming call always overlays (priority 1). Speed camera overlays on non-navigation screens; during navigation, sets ALERT flag in the nav payload header so firmware shows a subtle indicator without hiding turn instructions (priority 2). Only one overlay at a time; call replaces blitzer.

---

## Architecture

### System Overview

```
┌─────────────────┐        BLE GATT        ┌──────────────────────┐
│   iPhone App     │ ◄───────────────────► │  ESP32-S3 + AMOLED    │
│                  │                        │                       │
│  - CoreLocation  │   Screen payload       │  - BLE Server         │
│  - CoreMotion    │   (binary struct)       │  - LVGL UI renderer   │
│  - WeatherKit    │                        │  - Screen state FSM   │
│  - CallKit       │   Control commands     │  - 12V buck powered   │
│  - EventKit      │   (switch screen,      │                       │
│  - MediaPlayer   │    brightness, etc.)   │                       │
│  - MapKit        │                        │                       │
└─────────────────┘                        └──────────────────────┘
```

### BLE Protocol

**Service UUID:** Custom 128-bit UUID (TBD)

| Characteristic | UUID | Direction | Description |
|---|---|---|---|
| `screen_data` | TBD | Phone → ESP32 (Write) | Screen payload — binary struct with screen ID + data fields |
| `control` | TBD | Phone → ESP32 (Write) | Commands: switch screen, set brightness, sleep/wake |
| `status` | TBD | ESP32 → Phone (Notify) | Device status: battery voltage, uptime, display state |

#### Screen Data Payload

```c
typedef struct {
    uint8_t  screen_id;       // 0x01 = nav, 0x02 = speed, etc.
    uint8_t  flags;           // bitfield: alert priority, night mode
    uint16_t data_length;     // length of screen-specific payload
    uint8_t  data[];          // screen-specific struct (variable)
} screen_payload_t;
```

Example: Navigation screen data

```c
typedef struct {
    int32_t  lat;             // latitude × 1e7
    int32_t  lng;             // longitude × 1e7
    uint16_t speed_kmh_x10;  // speed × 10 (e.g. 672 = 67.2 km/h)
    uint16_t heading_x10;    // heading × 10 (e.g. 0420 = 42.0°)
    uint16_t distance_m;     // distance to next maneuver in meters
    uint8_t  maneuver_type;  // enum: straight, left, right, u-turn, arrive...
    uint8_t  street_name[32];// UTF-8, null-terminated
    uint16_t eta_minutes;    // minutes to destination
    uint16_t remaining_km_x10;
} nav_data_t;
```

**Update frequency:**
- Navigation / Speed / Lean: 1 Hz (every second)
- Weather / Calendar / Fuel: On change or every 60s
- Alerts (Call, Blitzer): Immediate push
- Clock: Every 60s (ESP32 RTC handles seconds locally)

### ESP32 Firmware

- **Framework:** ESP-IDF (preferred for BLE stability) or Arduino
- **UI Library:** LVGL v9 — round display support, smooth animations, efficient partial redraws on AMOLED
- **State Machine:** Simple FSM per screen. On receiving `screen_data`, decode `screen_id`, update corresponding LVGL screen object, trigger redraw.
- **Night Mode:** AMOLED brightness PWM control. Auto-dim based on flag from iPhone (ambient light sensor) or time-based.
- **OTA Updates:** Via BLE from iOS app. Firmware binaries hosted on GitHub Releases (tag format `fw-vX.Y.Z`). iOS checks on launch (24h cache), offers update in Mehr tab, transfers via chunked BLE write.

### iOS Companion App

- **Language:** Swift
- **Min iOS:** 17.0 (CoreBluetooth, WeatherKit, CallKit all stable)
- **Architecture:** Lightweight — no server, no accounts, no RevenueCat. Pure local app.
- **Key Frameworks:**
  - `CoreBluetooth` — BLE central, GATT write to ESP32
  - `CoreLocation` — GPS position, speed, heading, altitude
  - `CoreMotion` — Accelerometer for lean angle calculation
  - `WeatherKit` — Current conditions at location
  - `CallKit` / `CXCallObserver` — Incoming call detection
  - `EventKit` — Next calendar event
  - `MediaPlayer` — Now playing info
  - `MapKit` / custom nav integration — Turn-by-turn data
- **Background Modes:** BLE accessory, location updates — app must keep pushing data while backgrounded during a ride.
- **Screen Config UI:** Simple list to enable/disable screens, set order, configure alert thresholds (e.g. Blitzer warning distance).

---

## Navigation Data Source

The hardest part is getting turn-by-turn maneuver data programmatically on iOS.

### Options

| Approach | Pros | Cons |
|---|---|---|
| **MapKit Directions API** | Native, free, reliable | No real-time re-routing, need to poll/manage route manually |
| **Google Maps SDK** | Best routing data | Requires API key, costs at scale, complex SDK |
| **OsmAnd URL scheme** | Free, offline maps | No direct data API — screen scraping or accessibility hacks |
| **Custom routing (OSRM/Valhalla)** | Full control, free | Need self-hosted server or on-device routing engine |
| **Apple CarPlay-style integration** | Best UX | Not available for third-party BLE displays |

**Recommended approach:** Start with **MapKit Directions API** for basic turn-by-turn. Pre-calculate route, track position along route polyline, derive next maneuver from route steps. Upgrade to OSRM/Valhalla later if needed.

---

## Blitzer / Radar Warning Data

### Legal Status (Switzerland)

Radar warning apps are **legal to use** in Switzerland as of 2024 (Bundesgericht ruling). Displaying camera locations on a map or giving proximity warnings is permitted. Active radar detectors (hardware) remain illegal.

### Data Sources

- **OpenStreetMap** — Speed camera nodes tagged `highway=speed_camera`
- **Community databases** — Various open datasets of fixed camera locations (CH, DE, AT, IT, FR)
- **Import as local DB** in the iOS app, query against current GPS position
- Trigger alert on ESP32 when within configurable radius (default: 500m)

---

## Development Phases

### Phase 1 — Hardware proof of concept

- [ ] Order Waveshare ESP32-S3 1.75" AMOLED (non-GPS version)
- [ ] Order buck converter + cable gland + O-rings
- [ ] Remove Tripper Pod, measure cavity, test fit
- [ ] Flash basic LVGL demo to confirm display works
- [ ] Wire 12V from bike → buck converter → ESP32, confirm stable power

### Phase 2 — BLE + Clock screen

- [ ] Implement BLE GATT server on ESP32 (single characteristic)
- [ ] Build minimal iOS app: CoreBluetooth central, discover + connect + write
- [ ] Send time/date from iPhone → ESP32, render clock screen
- [ ] Validate BLE stability over 1+ hour ride

### Phase 3 — Speed + Compass

- [ ] Add CoreLocation to iOS app (speed, heading, altitude)
- [ ] Define binary struct for speed screen
- [ ] Render speed + compass screens on ESP32 with LVGL
- [ ] Test GPS accuracy and update frequency while riding

### Phase 4 — Navigation

- [ ] Implement MapKit Directions route calculation
- [ ] Track position along route, derive next maneuver
- [ ] Encode nav data in BLE payload
- [ ] Render navigation screen with turn arrows on ESP32
- [ ] Test on real routes around Basel

### Phase 5 — Secondary screens

- [ ] Weather (WeatherKit)
- [ ] Music (MPNowPlayingInfoCenter)
- [ ] Trip stats (accumulated location data)
- [ ] Lean angle (CoreMotion accelerometer → trigonometry)
- [ ] Fuel estimate (manual fill log + distance tracking)
- [ ] Calendar (EventKit next event)

### Phase 6 — Alerts

- [ ] Incoming call detection (CXCallObserver)
- [ ] Blitzer DB import + proximity alerting
- [ ] Alert overlay system on ESP32 (priority-based screen interruption)

### Phase 7 — Polish + Waterproof

- [ ] Final housing solution (reuse Tripper shell or custom print)
- [ ] Seal and waterproof
- [ ] Night mode / auto-brightness
- [ ] OTA firmware update via WiFi
- [ ] Extended ride testing (rain, heat, vibration)

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Waveshare board doesn't fit in Tripper Pod shell | Medium | Measure before ordering. Fallback: custom 3D-printed housing |
| BLE disconnects during rides (vibration, distance) | High | ESP32 BLE is robust at <1m range. Implement auto-reconnect on both sides. Show last-known data on disconnect |
| iOS background BLE throttling | High | Use `CBCentralManager` with `bluetooth-central` background mode. Test extensively with screen off |
| AMOLED not readable in direct sunlight | Medium | AMOLED has excellent contrast. Waveshare board rated for outdoor use. Add brightness control |
| Waterproofing failure | High | Conformal coat PCB as baseline. Test with garden hose before real rain rides |
| 12V power noise from bike alternator | Low | Buck converter + capacitor smoothing. ESP32 is tolerant of minor voltage ripple |

---

## Success Criteria

1. Display survives a full-day ride (8+ hours) without crash or disconnect
2. Navigation arrows are readable at a glance at 80 km/h
3. BLE reconnects automatically within 5 seconds after any disconnect
4. Housing survives a 30-minute rain ride without moisture ingress
5. Screen switching from iPhone takes <500ms

---

## Future Ideas (Post-MVP)

- **Group ride mode** — show distance/direction to riding buddy via shared GPS over internet
- **Dashcam trigger** — BLE command to start/stop recording on a GoPro
- **Tire pressure** — BLE TPMS sensors → ESP32 → display
- **Open-source release** — publish firmware, iOS app, 3D print files, BLE protocol spec on GitHub
- **Modular screen plugins** — let others contribute screen layouts via a simple JSON/config format
