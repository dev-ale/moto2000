# ADR 0004: Test strategy — tests-first, bike-free

Date: 2026-04-09
Status: Accepted

## Context

The device is meant to be glanced at while riding a motorcycle. Developing features
only when seated on the bike is impractical and unsafe. The project must be fully
testable and demoable from a desk.

The PRD also requires "professional setup from the start, tests for everything".

## Decision

Every feature slice must satisfy the following before it is considered done:

1. **Pure core, thin shell.** Domain logic (lean angle math, route tracking, trip
   accumulators, alert priority FSM) is expressed as pure functions or deterministic
   reducers, tested exhaustively with fixtures.
2. **Protocol-oriented integrations.** Every iOS system framework lives behind a
   Swift protocol with a real implementation and at least one fake or scenario-driven
   mock. No XCTest test may touch a real `CLLocationManager`, `MPNowPlayingInfoCenter`,
   or similar.
3. **Shared binary fixtures.** The BLE wire format is validated by round-trip tests
   that exercise both the Swift encoder and the C decoder against the same bytes in
   `protocol/fixtures/`.
4. **Host-runnable firmware tests.** Firmware components expose host-compilable code
   with Unity tests that run on Linux in CI. On-device tests are reserved for code
   that physically cannot run off-target.
5. **Screen snapshot tests.** Every LVGL screen is rendered by the LVGL SDL host
   simulator in CI and diffed against a committed PNG snapshot.
6. **Ride simulator scenarios.** Every feature slice ships at least one scenario
   file under `app/ios/Fixtures/scenarios/` that exercises it end-to-end into a real
   ESP32 or the host simulator — see Slice 1.5.

Tests are the definition of done. A slice without tests is not merged.

## Consequences

Positive:

- Development velocity stays high year-round, not just in riding season
- Regressions surface in CI, not on a mountain pass
- Onboarding contributors is straightforward: read the fixtures, run the tests

Negative:

- Higher upfront cost on each slice
- Requires discipline to keep the simulator fixtures in sync with reality

## See also

- ADR 0002 (Tuist + SwiftPM) — enables fast unit-test feedback loops
- ADR 0005 (iOS 18) — required for some mock-friendly APIs
- Slice 1.5 — Ride simulator & mock data harness
