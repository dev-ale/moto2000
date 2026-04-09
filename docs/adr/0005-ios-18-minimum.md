# ADR 0005: iOS 18 minimum deployment target

Date: 2026-04-09
Status: Accepted

## Context

The PRD initially suggested iOS 17. The app is a single-user personal project running
on the owner's own iPhone, so we are free to pick an aggressive minimum.

## Decision

Minimum deployment target: **iOS 18.0**.

## Consequences

Positive:

- Access to the latest SwiftUI, Observation, and Swift Testing APIs
- Newer CoreBluetooth background-delivery improvements
- Newer WeatherKit rate-limit behavior
- Simpler code (no OS-version branching)

Negative:

- Cannot be installed on iPhones below iOS 18 — acceptable, owner's device meets this
- Some third-party Swift packages may not yet set `iOS(.v18)` — we will vendor or
  patch as needed
