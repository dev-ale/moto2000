# ADR 0002: Tuist + SwiftPM for the iOS app

Date: 2026-04-09
Status: Accepted

## Context

The iOS companion app will grow to contain multiple feature modules (BLE, location,
weather, music, calls, calendar, motion, navigation), each with its own unit tests,
and must be developable + testable from a self-hosted CI runner.

Options considered: plain `.xcodeproj`, XcodeGen, Tuist, and SwiftPM-only.

## Decision

Use **Tuist** to generate the Xcode project, and **SwiftPM** for local Swift packages
(feature modules, BLE protocol codec, test utilities).

## Consequences

Positive:

- `.xcodeproj` stays out of git — no merge conflicts, clean diffs
- Swift-based `Project.swift` manifests — type-checked and refactorable
- Strong module boundaries enforced by package structure from day one
- Generated project is reproducible in CI
- Local Swift packages give us fast unit-test feedback loops without booting the app

Negative:

- Tuist is an extra tool contributors must install
- Slightly more ceremony than a single `.xcodeproj`

Rejected alternatives:

- **Plain `.xcodeproj`** — noisy diffs, merge conflicts, no module enforcement
- **XcodeGen** — YAML manifests are less ergonomic than Swift, weaker module story
- **SwiftPM-only** — no iOS app target, can't build a shippable `.ipa`
