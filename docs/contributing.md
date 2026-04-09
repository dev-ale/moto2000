# Contributing to ScramScreen

ScramScreen is a personal motorcycle dashboard project, but it is built to
professional standards from the start. Tests are mandatory. CI is the source of
truth. This document explains how to set up a development environment and what
is expected of every change.

## Prerequisites

### iOS app (`app/ios/`)

- macOS with Xcode 16+
- [Tuist](https://tuist.io) — install the version pinned in `.tuist-version`:

  ```sh
  curl -Ls https://install.tuist.io | bash
  mise use tuist@$(cat .tuist-version)   # or use `tuistenv`
  ```

- [SwiftLint](https://github.com/realm/SwiftLint) and
  [swift-format](https://github.com/swiftlang/swift-format). Install via Homebrew:

  ```sh
  brew install swiftlint swift-format
  ```

- An Apple Developer Team ID. Copy `app/ios/.env.tuist.example` to
  `app/ios/.env.tuist` and fill in your team ID. This file is gitignored.

### ESP32 firmware (`hardware/firmware/`)

- [ESP-IDF v5.3](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32s3/get-started/index.html)
  targeting `esp32s3`
- `cmake`, `ninja`, `clang-format`, `cppcheck` (host tests + lint)

### Repo-wide tooling

- [`pre-commit`](https://pre-commit.com): `pip install pre-commit && pre-commit install`

## First-time setup

```sh
# iOS
cd app/ios
cp .env.tuist.example .env.tuist   # then edit with your team ID
tuist install
tuist generate

# Firmware (ESP-IDF)
cd hardware/firmware
idf.py set-target esp32s3
idf.py build

# Firmware host tests (Linux/macOS, no ESP-IDF needed)
cd hardware/firmware/test/host
cmake -B build
cmake --build build
ctest --test-dir build --output-on-failure

# Pre-commit
pre-commit install
```

## Branching and commits

- **Branch off `main`** for every change. No direct commits to `main` on GitHub
  once branch protection is configured (see below).
- **Conventional Commits** are enforced by the `Commits` workflow and by
  `pre-commit` on `commit-msg`. Examples:
  - `feat(ble): add control characteristic`
  - `fix(ios): guard against nil CLLocation course`
  - `chore(ci): pin actions to v4`
- Keep commits small and focused. Prefer many small commits in a PR over one
  giant squash.

## Definition of done

Every slice merges only when it meets the professional bar from
[ADR-0004](./adr/0004-test-strategy.md):

1. Pure domain logic covered by unit tests against fixtures.
2. Every iOS system framework sits behind a protocol with a mock.
3. BLE wire format validated by round-trip tests against shared binary
   fixtures in `protocol/fixtures/`.
4. Firmware logic runs in the Unity host harness where possible.
5. Every LVGL screen has a host-simulator snapshot test (from Slice 1.5 onward).
6. The feature is demoable via the ride simulator without the bike
   (Slice 1.5 onward).
7. `tuist generate && xcodebuild test` and `ctest` pass green locally.
8. CI is green.

## Branch protection (to configure on GitHub)

On `main`:

- Require PR review before merging.
- Require status checks to pass:
  - `iOS / Lint (SwiftLint + swift-format)`
  - `iOS / BLEProtocol package tests`
  - `iOS / Build & test`
  - `Firmware / Unity host tests`
  - `Firmware / clang-format + cppcheck`
  - `Firmware / ESP-IDF build (esp32s3)`
  - `Commits / Conventional Commits`
- Require branches to be up to date before merging.
- Require linear history.
- Do not allow force pushes.

## Secrets to configure on GitHub

- `TUIST_DEVELOPMENT_TEAM` — your Apple Developer Team ID, consumed by the iOS
  workflow so Tuist-generated projects carry a signing identity in CI.
