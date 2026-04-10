# ScramScreen

A custom-built, waterproof, round AMOLED display that replaces the stock Royal Enfield Tripper Navigation pod on a Scram 411. It connects via BLE to an iOS companion app, turning the locked-down OEM navigation puck into a fully programmable motorcycle dashboard.

**Status:** iOS app implemented, firmware rendering complete, hardware integration next
**Owner:** Alejandro
**Target:** Personal use (single unit), open-source potential

## Why

The Royal Enfield Tripper Pod is locked to the proprietary RE app with Google Maps turn-by-turn only. It can't show custom data, use alternative navigation, or integrate with anything else. No public reverse-engineering of the Tripper BLE protocol exists, so a firmware flash isn't practical. The solution is a full hardware replacement reusing the existing handlebar mount.

## Architecture

```
┌─────────────────┐        BLE GATT        ┌──────────────────────┐
│   iPhone App    │ ◄───────────────────► │  ESP32-S3 + AMOLED   │
│                 │                        │                      │
│  - CoreLocation │   Screen payload       │  - BLE Server        │
│  - CoreMotion   │   (binary struct)      │  - LVGL UI renderer  │
│  - WeatherKit   │                        │  - Screen state FSM  │
│  - CallKit      │   Control commands     │  - 12V buck powered  │
│  - EventKit     │                        │                      │
│  - MediaPlayer  │                        │                      │
│  - MapKit       │                        │                      │
└─────────────────┘                        └──────────────────────┘
```

The ESP32 is a dumb display — all logic, data fetching, and routing lives on the iPhone. The firmware decodes incoming BLE payloads, caches them per screen, and renders via LVGL. A handlebar button cycles through screens locally using the cached payloads (no BLE round-trip). iOS is notified of screen changes via `SCREEN_CHANGED` status notifications.

## Hardware

| Part | Spec | Est. Price |
|---|---|---|
| Waveshare ESP32-S3 1.75" AMOLED Round Display | 466×466px, QSPI, BLE 5.0 + WiFi | ~CHF 25 |
| Mini buck converter | 12V → 5V (MP1584 or similar) | ~CHF 3 |
| IP67 cable gland | PG7 | ~CHF 2 |
| Silicone gasket / O-ring | Housing seal | ~CHF 2 |
| Housing | Reuse Tripper shell or 3D-print PETG + acrylic lens | ~CHF 0-10 |

**Total BOM: ~CHF 35-40**

Power is tapped from the bike's 12V ignition-switched accessory line through a buck converter to the ESP32's 5V input. No battery, no standby drain — the display powers off with the ignition.

## Screens

**Primary (riding)** — Navigation, Speed + Heading, Compass
**Secondary (glanceable)** — Weather, Trip Stats, Music, Lean Angle
**Alerts (overlay)** — Radar/Blitzer, Incoming Call, Fuel Estimate
**Passive (idle)** — Altitude Profile, Next Appointment, Clock

Screens are cycled via a **handlebar button** wired to the ESP32 GPIO. No auto-rotation — the rider controls which screen is visible. Alerts (incoming call, speed camera) interrupt via overlay: incoming call always overlays; speed camera during navigation sets an ALERT flag in the nav payload instead of hiding turn instructions.

## BLE Protocol

A custom GATT service with three characteristics:

| Characteristic | Direction | Description |
|---|---|---|
| `screen_data` | Phone → ESP32 | Screen payload: binary struct with screen ID + data |
| `control` | Phone → ESP32 | Switch screen, set brightness, sleep/wake |
| `status` | ESP32 → Phone | Device status, `SCREEN_CHANGED` notifications |

Payloads are packed binary structs, not JSON, to keep BLE writes small and fast. Navigation/Speed/Lean update at 1 Hz; Weather/Calendar/Fuel update on change or every 60s; alerts push immediately.

See [`scram-display-prd.md`](scram-display-prd.md) for full struct definitions and update frequencies.

## Software

**ESP32 firmware**
- ESP-IDF v5.3 targeting `esp32s3` ([ADR-0001](docs/adr/0001-esp-idf-over-arduino.md))
- LVGL v9.2 for UI — round display support, partial redraws, smooth anims ([ADR-0003](docs/adr/0003-lvgl-v9.md))
- Unity host-test harness runs core firmware logic on Linux CI with no hardware
- Screen FSM (active, alert overlay, sleep) + payload cache + screen order manager
- Handlebar button GPIO handler cycles screens locally from cached payloads
- OTA firmware updates via BLE (binaries hosted on GitHub Releases)

**iOS companion app**
- Swift 6, iOS 18+ minimum ([ADR-0005](docs/adr/0005-ios-18-minimum.md))
- Project generated with Tuist, no `.xcodeproj` in git ([ADR-0002](docs/adr/0002-tuist-and-swiftpm.md))
- No server, no accounts — pure local app
- `CoreBluetooth`, `CoreLocation`, `CoreMotion`, `WeatherKit`, `CallKit`, `EventKit`, `MediaPlayer`, `MapKit`
- `RideSession` actor orchestrates all 13 data services, `PayloadScheduler` manages BLE bandwidth
- Runs in background with `bluetooth-central` + `location` modes during rides
- Full implementation details: [`docs/ios-app-prd.md`](docs/ios-app-prd.md)

## Navigation

Uses **MapKit Directions API**. Rider enters a destination in the app before riding (MKLocalSearchCompleter autocomplete). Route is tracked along the polyline with automatic rerouting when >100m off-route for >10 seconds. Navigation ends silently on arrival.

## Blitzer / Radar Warnings

Legal in Switzerland (Bundesgericht ruling, 2024) for passive proximity warnings. 1,249 Swiss speed cameras bundled as SQLite from OpenStreetMap (`highway=speed_camera`), queried locally against GPS position, alert fires at a configurable radius (default 500m). Database updated with each app release via `tools/fetch-speed-cameras/`.

## Roadmap

**Completed:**
- BLE protocol codec (Swift + C) with 13 screen types + golden fixtures
- All 13 LVGL screen renderers (host simulator + snapshot tests)
- iOS app: RideSession orchestration, all data services, PayloadScheduler with alert priority
- iOS app: Navigation search + auto-reroute, lean angle auto-calibration, fuel tracking, trip history
- iOS app: Calendar selection, night mode override, OTA update UI, background execution
- Firmware: payload cache, screen order manager, button handler components
- Speed camera database: 1,249 Swiss cameras from OSM

**Next:**
1. **Hardware bring-up** — Order parts, fit test in Tripper shell, validate 12V power
2. **BLE server + LVGL integration** — Wire firmware components to real hardware
3. **Handlebar button wiring** — GPIO interrupt on real hardware
4. **Extended ride testing** — 8+ hour rides, rain, vibration
5. **Waterproof housing** — Final seal and assembly

## Success Criteria

- Survives a full-day ride (8+ hours) without crash or disconnect
- Navigation arrows readable at a glance at 80 km/h
- BLE reconnects within 5 seconds after any disconnect
- Housing survives a 30-minute rain ride without ingress
- Screen switch from iPhone in <500ms

## Non-Goals

- Standalone GPS on the display (iPhone handles all location)
- Touch interaction (impractical with gloves)
- OBD/ECU integration (Scram 411 has no OBD port)
- Android support (iOS only)
- Mass production or commercial sale

## Repo Structure

```
.
├── app/ios/                  # SwiftUI companion app (Tuist + XCTest)
│   ├── Sources/              #   App views (HomeView, FahrtenView, TankView, MehrView, ...)
│   ├── Packages/
│   │   ├── BLEProtocol/      #   BLE codec (13 screen types + control + status)
│   │   ├── BLECentralClient/ #   CoreBluetooth wrapper + reconnect FSM
│   │   ├── ScramCore/        #   Business logic (RideSession, 15 services, PayloadScheduler)
│   │   └── RideSimulatorKit/ #   Scenario playback for testing
│   └── Project.swift         #   Tuist project definition
├── hardware/
│   ├── firmware/             # ESP-IDF project for ESP32-S3
│   │   ├── components/       #   ble_protocol, screen_fsm, payload_cache, screen_order, ota_fsm
│   │   ├── host-sim/         #   LVGL host simulator + snapshot tests (all 13 screens)
│   │   └── test/host/        #   Unity C unit tests
│   └── cad/                  # Enclosure CAD and 3D print files
├── protocol/
│   └── fixtures/             # Shared golden binary fixtures for codec round-trip tests
├── tools/
│   └── fetch-speed-cameras/  # Overpass API → SQLite build script (Switzerland)
├── docs/
│   ├── prd.md                # Product requirements doc
│   ├── ios-app-prd.md        # iOS app implementation PRD
│   ├── ble-protocol.md       # BLE wire format spec
│   ├── contributing.md       # Dev setup, commit style, branch protection
│   └── adr/                  # Architecture decision records
└── .github/workflows/        # iOS, firmware, commit-lint CI
```

Start here:

- [`docs/prd.md`](docs/prd.md) — Product requirements doc
- [`docs/ios-app-prd.md`](docs/ios-app-prd.md) — iOS app implementation PRD (all design decisions)
- [`docs/contributing.md`](docs/contributing.md) — First-time setup, tests, and the bar for merging
- [`docs/ble-protocol.md`](docs/ble-protocol.md) — BLE wire format spec
- [`docs/adr/`](docs/adr) — Stack decisions
- [`docs/mockups.html`](docs/mockups.html) — Screen mockups
