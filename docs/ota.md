# OTA Firmware Update

This document describes the over-the-air (OTA) firmware update system for
ScramScreen. The system covers version checking, firmware downloading,
HMAC-SHA256 signature verification, flashing, and rollback-on-boot-failure.

## Overview

OTA updates are WiFi-based and initiated either by the iOS app (via a BLE
control command) or automatically on boot. The ESP32 handles the entire
download-verify-apply-reboot cycle; the iOS app only triggers the check and
observes progress.

## State Machine

The OTA FSM lives at `hardware/firmware/components/ota_fsm/` and is pure C
with no ESP-IDF dependencies. It is host-testable under Unity.

```
                    CHECK_REQUESTED
    ┌──────┐  ─────────────────────►  ┌──────────┐
    │ IDLE │                          │ CHECKING │
    └──┬───┘  ◄─────────────────────  └────┬─────┘
       │         NO_UPDATE (NONE)          │
       │                          VERSION_AVAILABLE
       │                                   │
       │                                   ▼
       │                          ┌─────────────┐
       │                          │ DOWNLOADING  │◄──┐
       │                          └──────┬───────┘   │ DOWNLOAD_FAILED
       │                                 │           │ (retry < max)
       │                    DOWNLOAD_COMPLETE        │
       │                                 │     ──────┘
       │                                 ▼
       │                          ┌───────────┐
       │                          │ VERIFYING  │
       │                          └─────┬──────┘
       │                                │
       │                           VERIFY_OK
       │                                │
       │                                ▼
       │                          ┌──────────┐
       │                          │ APPLYING  │
       │                          └─────┬─────┘
       │                                │
       │                           APPLY_OK
       │                                │
       │                                ▼
       │       BOOT_CONFIRMED    ┌───────────┐    BOOT_FAILED
       │  ◄──────────────────────│ REBOOTING │──────────────►  ┌──────────┐
       │     (CONFIRM_BOOT)      └───────────┘   (ROLLBACK)    │ ROLLBACK │
       │                                                       └────┬─────┘
       │                                                            │ RESET
       │  ◄─────────────────────────────────────────────────────────┘
       │
       │         RESET           ┌───────┐
       └─────────────────────────│ ERROR │
                                 └───────┘

    Any failure (DOWNLOAD_FAILED after max retries, VERIFY_FAILED,
    APPLY_FAILED) transitions to ERROR. ERROR + RESET → IDLE.
```

### Download Retries

The FSM retries download failures up to `max_retries` times (default 3)
before entering ERROR. The retry counter resets when a new check is
initiated.

### Events and Actions

| State        | Event              | Next State    | Action          |
|--------------|--------------------|---------------|-----------------|
| IDLE         | CHECK_REQUESTED    | CHECKING      | START_CHECK     |
| CHECKING     | VERSION_AVAILABLE  | DOWNLOADING   | START_DOWNLOAD  |
| CHECKING     | NO_UPDATE          | IDLE          | NONE            |
| DOWNLOADING  | DOWNLOAD_COMPLETE  | VERIFYING     | START_VERIFY    |
| DOWNLOADING  | DOWNLOAD_FAILED    | DOWNLOADING*  | START_DOWNLOAD  |
| DOWNLOADING  | DOWNLOAD_FAILED    | ERROR**       | REPORT_ERROR    |
| VERIFYING    | VERIFY_OK          | APPLYING      | START_APPLY     |
| VERIFYING    | VERIFY_FAILED      | ERROR         | REPORT_ERROR    |
| APPLYING     | APPLY_OK           | REBOOTING     | REBOOT          |
| APPLYING     | APPLY_FAILED       | ERROR         | REPORT_ERROR    |
| REBOOTING    | BOOT_CONFIRMED     | IDLE          | CONFIRM_BOOT    |
| REBOOTING    | BOOT_FAILED        | ROLLBACK      | ROLLBACK        |
| ROLLBACK     | RESET              | IDLE          | NONE            |
| ERROR        | RESET              | IDLE          | NONE            |

\* retry_count < max_retries  
\** retry_count >= max_retries

## Signature Verification

### Scheme: HMAC-SHA256

The MVP uses HMAC-SHA256 for firmware image signing. This was chosen over
Ed25519 because:

1. It requires only a single-file SHA256 dependency (vendored from Brad
   Conte's crypto-algorithms, public domain).
2. HMAC-SHA256 is simpler to implement correctly on embedded targets.
3. The signing key is a shared secret stored in the CI environment and on the
   ESP32 — acceptable for a personal project where the device is physically
   controlled.

A future slice may upgrade to Ed25519 (asymmetric) signing using monocypher
or tweetnacl for stronger security properties (the signer need not share a
secret with the verifier).

### Signing Process

1. CI builds the firmware binary on tagged releases (`v*`).
2. The binary is signed with:
   ```
   openssl dgst -sha256 -hmac "$OTA_SIGNING_KEY" -binary \
     build/scramscreen.bin > build/scramscreen.sig
   ```
3. Both `.bin` and `.sig` are uploaded as release artifacts.
4. The ESP32 downloads both, verifies the HMAC, and only then writes to flash.

### Verification

```c
ota_verify_hmac_sha256(&key, firmware_data, firmware_len, signature, 32);
```

The implementation uses constant-time comparison to prevent timing
side-channels.

## Update Source

The update source is a GitHub release asset. The ESP32 checks the GitHub
Releases API for the latest `v*` tag, compares the version against its
running firmware, and downloads if newer.

Configuration is compile-time for now:
- Repository URL
- Current firmware version (baked into the binary)

## Rollback Strategy

ESP-IDF provides a dual-partition OTA scheme:

1. The new firmware is written to the inactive OTA partition.
2. `esp_ota_set_boot_partition()` marks the new partition as boot target.
3. On reboot, the bootloader loads the new partition.
4. The new firmware must call `esp_ota_mark_app_valid_and_cancel_rollback()`
   within a configurable timeout (default: 30 seconds).
5. If the confirmation does not arrive (crash, hang, watchdog), the bootloader
   automatically rolls back to the previous partition on the next reboot.

The OTA FSM models this as:
- `REBOOTING` + `BOOT_CONFIRMED` → `IDLE` (success)
- `REBOOTING` + `BOOT_FAILED` → `ROLLBACK` → `IDLE` (automatic recovery)

## Manual Recovery

If both OTA partitions contain broken firmware:

1. Connect the ESP32 via USB.
2. Hold the BOOT button and press RESET to enter download mode.
3. Flash a known-good binary with `idf.py flash`.

## iOS Integration

The iOS app sends a `checkForOTAUpdate` control command (0x06) over the BLE
control characteristic. The ESP32 receives this and begins the OTA check
sequence. Progress is reported back over the BLE status characteristic.

### Types

- `FirmwareVersion` — Sendable Comparable struct (major.minor.patch)
- `OTAService` — actor that holds current version and emits control commands
- `OTAStatusObserver` — protocol for observing ESP32 OTA progress (stubbed)

## CI Configuration

The `release-artifact` job in `.github/workflows/firmware.yml` runs only on
tagged releases (`v*`). It builds the firmware in the ESP-IDF container and
uploads the binary as a GitHub Actions artifact.

### Required GitHub Secrets

- `OTA_SIGNING_KEY` — 32-byte hex-encoded HMAC-SHA256 key used to sign
  firmware binaries. Generate with: `openssl rand -hex 32`

The same key must be provisioned on the ESP32 (compiled into the firmware or
stored in NVS).

## What's Implemented vs Hardware-Dependent

### Implemented (software-only, this slice)

- OTA state machine (pure C, Unity-tested)
- Firmware version comparison (C + Swift)
- HMAC-SHA256 signature verification (vendored SHA256, RFC 4231 tested)
- iOS check-for-update UI boundary (OTAService actor)
- BLE control command 0x06 (checkForOTAUpdate)
- CI release artifact job (config only)
- This documentation

### Deferred to hardware bring-up

- WiFi connection + HTTP download of firmware images
- `esp_ota_begin` / `esp_ota_write` / `esp_ota_end` integration
- Rollback-on-boot-failure end-to-end verification
- NVS storage of the signing key
- Status characteristic reporting of OTA progress
- Manual end-to-end OTA test in bring-up report
