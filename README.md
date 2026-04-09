# ScramScreen

A custom-built, waterproof, round AMOLED display that replaces the stock Royal Enfield Tripper Navigation pod on a Scram 411. It connects via BLE to an iOS companion app, turning the locked-down OEM navigation puck into a fully programmable motorcycle dashboard.

**Status:** Concept / Hardware prototyping
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

The ESP32 is a dumb display — all logic, data fetching, and routing lives on the iPhone. The firmware just decodes incoming BLE payloads and renders the corresponding LVGL screen.

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

Screens auto-switch on context (nav starts → nav screen, call comes in → call overlay, Blitzer in range → alert) and can be manually cycled from the iOS app.

## BLE Protocol

A custom GATT service with three characteristics:

| Characteristic | Direction | Description |
|---|---|---|
| `screen_data` | Phone → ESP32 | Screen payload: binary struct with screen ID + data |
| `control` | Phone → ESP32 | Switch screen, set brightness, sleep/wake |
| `status` | ESP32 → Phone | Device status: voltage, uptime, display state |

Payloads are packed binary structs, not JSON, to keep BLE writes small and fast. Navigation/Speed/Lean update at 1 Hz; Weather/Calendar/Fuel update on change or every 60s; alerts push immediately.

See [`scram-display-prd.md`](scram-display-prd.md) for full struct definitions and update frequencies.

## Software

**ESP32 firmware**
- ESP-IDF (preferred for BLE stability) or Arduino
- LVGL v9 for UI — round display support, partial redraws, smooth anims
- Simple FSM per screen; OTA updates via WiFi when available

**iOS companion app**
- Swift, iOS 17+
- No server, no accounts — pure local app
- `CoreBluetooth`, `CoreLocation`, `CoreMotion`, `WeatherKit`, `CallKit`, `EventKit`, `MediaPlayer`, `MapKit`
- Runs in background with `bluetooth-central` + location background modes to keep pushing data during rides

## Navigation

Start with **MapKit Directions API** — pre-calculate route, track position along the polyline, derive next maneuver from route steps. Upgrade to self-hosted OSRM/Valhalla later if needed.

## Blitzer / Radar Warnings

Legal in Switzerland (Bundesgericht ruling, 2024) for passive proximity warnings. Data imported from OpenStreetMap (`highway=speed_camera`) + community datasets, queried locally against GPS position, alert fires at a configurable radius (default 500m).

## Roadmap

1. **Hardware PoC** — Order parts, fit test in Tripper shell, flash LVGL demo, validate 12V power
2. **BLE + Clock** — GATT server on ESP32, minimal iOS central, render clock screen
3. **Speed + Compass** — CoreLocation → binary struct → LVGL gauges
4. **Navigation** — MapKit route → maneuver tracking → turn arrows
5. **Secondary screens** — Weather, music, trip stats, lean angle, fuel, calendar
6. **Alerts** — Call detection, Blitzer DB + proximity overlay
7. **Polish + Waterproof** — Final housing, night mode, OTA, extended ride testing

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
├── app/        # iOS companion app (Swift)
├── hardware/   # ESP32-S3 firmware, enclosure CAD, wiring
└── docs/       # PRD, mockups, protocol specs
```

- [`docs/prd.md`](docs/prd.md) — Full product requirements doc
- [`docs/mockups.html`](docs/mockups.html) — Screen mockups
- [`docs/mockups-extra.html`](docs/mockups-extra.html) — Additional mockups
