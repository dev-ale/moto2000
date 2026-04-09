# ADR 0001: Use ESP-IDF over Arduino for ESP32 firmware

Date: 2026-04-09
Status: Accepted

## Context

The ScramScreen firmware runs on a Waveshare ESP32-S3 1.75" AMOLED board. The PRD lists
two candidate frameworks: ESP-IDF and Arduino.

Requirements that drive the choice:

- Long-running, low-latency BLE GATT server with reconnect handling
- LVGL v9 rendering at reasonable frame rates
- Host-runnable unit tests (develop without hardware — see Slice 1.5)
- OTA update with signature verification and rollback on boot failure
- Deterministic build system suitable for CI

## Decision

Use **ESP-IDF v5.3** as the firmware framework.

## Consequences

Positive:

- First-class BLE stack (NimBLE) with stable reconnect primitives
- Official Unity test runner with a `linux` host target — core logic can run in CI
  without any hardware
- Native CMake build plays well with GitHub Actions and `clang-format`/`cppcheck`
- Built-in OTA, secure boot, and rollback support
- LVGL v9 ships as an IDF component

Negative:

- Steeper learning curve than Arduino
- More boilerplate for trivial peripherals

Rejected alternatives:

- **Arduino** — faster to prototype but weaker BLE stability story, no first-class
  host-test path, less control over OTA and partitioning. Rejected for a product
  intended to survive full-day rides.
