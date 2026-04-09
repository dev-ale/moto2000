# Background BLE and reconnect behavior

**Status:** Defined in Slice 17 (#19). On-device verification lands in a
later slice; this document is the contract every implementation must
satisfy.

## Goals

1. **Recover from transient disconnects within five seconds.** The link
   between the iPhone and the ScramScreen drops constantly in real-world
   riding — wind gusts, pocket movement, ESP32 brown-outs — and the rider
   must not have to touch the phone for the dashboard to come back.
2. **Never show stale data without warning.** The ESP32 keeps drawing the
   last known payload during an outage. Once the payload gets too old, the
   renderer raises the `STALE` flag so the rider knows the number they're
   looking at is no longer live.
3. **Stay deterministic and testable.** No wall-clock `sleep()` anywhere.
   Both sides expose pure state machines driven by an external clock so
   host tests replay disconnects in microseconds.

## Architecture

```
 +-------------------+        writes         +-------------------+
 | BLECentralClient  | --------------------> |     ScramScreen   |
 | (iOS, Swift)      | <-------------------- |     (ESP32)       |
 +-------------------+    notifications      +-------------------+
         |                                            |
         | owns                                       | owns
         v                                            v
 +-------------------+                       +-------------------+
 | ReconnectState    |                       | ble_reconnect_fsm |
 | Machine           |                       | (C)               |
 +-------------------+                       +-------------------+
         |                                            |
         v                                            v
 +-------------------+                       +-------------------+
 | LastKnownPayload  |                       | ble_payload_cache |
 | Cache (per        |                       | (per screen id)   |
 | ScreenID)         |                       +-------------------+
 +-------------------+
```

Both sides run **their own** reconnect FSM with **the same backoff
schedule**. The iOS FSM decides when to rescan / re-connect; the ESP32 FSM
decides when to re-advertise / go back to sleep. Neither side trusts the
other to drive the loop.

## Reconnect state machine

The FSM is identical on both sides (modulo idioms). States:

```
          +------ startRequested / advertise
          |
     +----v-------+  didDisconnect   +-------------+
     |   IDLE /   |----------------->|   BACKOFF   |
     | DISCONNECTED|                 |  (attempt   |
     +----^-------+                  |   N, wake   |
          |                          |   at T)     |
          | stopRequested            +------+------+
          |                                 |
          |                      reconnectTick where
          |                      now >= wake
          |                                 |
     +----+-------+                         v
     |  CONNECTED |<-- didConnect --+  ADVERTISING /
     |            |                 |  CONNECTING
     +------------+                 +-------------+
           ^                                 |
           |            didDisconnect        |
           +---------------------------------+
                (bumps attempt, schedules
                 next BACKOFF slot)
```

State labels differ slightly between the two codebases:

| iOS (`ConnectionState`) | ESP32 (`ble_reconnect_state_t`) |
| ----------------------- | ------------------------------- |
| `.idle` / `.disconnected` | `BLE_RC_DISCONNECTED`         |
| `.scanning` / `.connecting` / `.reconnecting` | `BLE_RC_ADVERTISING` |
| `.connected`            | `BLE_RC_CONNECTED`              |
| (implicit in `.reconnecting` delay) | `BLE_RC_BACKOFF`   |

### Backoff schedule

Both FSMs use the same millisecond schedule, indexed by 1-based attempt:

| Attempt | Delay (ms) |
| ------: | ---------: |
|       1 |        100 |
|       2 |        200 |
|       3 |        400 |
|       4 |        800 |
|       5 |       1600 |
|      6+ |  3000 (cap) |

The sum of the first four slots is 1500 ms; by the time the FSM commits
to its fifth attempt it has waited 3100 ms, which still leaves roughly
1.9 seconds of headroom under the **five-second reconnect budget**. The
integration test `IntegrationReconnectTests.testReconnectAcrossBasel
CityLoopScenario` asserts this latency against a `VirtualClock`.

### Terminal disconnects

A disconnect with reason `userInitiated`, `unauthorized`, or `bluetoothOff`
is **terminal** — the FSM issues `cancelAll` and stops. A higher layer
must call `startRequested` again (e.g. on a `CBCentralManager` `.poweredOn`
callback) to restart the loop.

## Last-known-payload cache

During an outage the iOS UI renders from `LastKnownPayloadCache` and the
ESP32 renders from `ble_payload_cache_t`. Both caches:

- Store one entry per screen id.
- Timestamp every mutation with a caller-supplied `now` so host tests
  drive them with a virtual clock.
- Report a "stale" condition once an entry exceeds a configurable
  threshold (default 2 seconds).
- Return fresh / stale independently per screen — the rider's live speed
  can be stale while the clock screen is still current.

On the ESP32 side, the staleness verdict is what drives the `STALE` flag
in the screen header. See `docs/ble-protocol.md` §Status notifications.

## iOS background-BLE behavior

Apple's Core Bluetooth in the background imposes three constraints the
reconnect FSM must respect:

1. **Scan filters are required.** Background scanning without a service
   UUID filter is silently dropped by iOS. The client wraps every
   `scanForPeripherals` call with the ScramScreen service UUID from
   `BLEProtocol.ProtocolConstants`.
2. **No wake-on-RSSI.** iOS does not wake the app on advertising alone —
   it only wakes on a completed connection. The reconnect loop therefore
   relies on `CBCentralManager.connect(peripheral:)` being called with
   `CBConnectPeripheralOptionNotifyOnConnectionKey` so the OS delivers the
   connection callback while the app is suspended.
3. **Timers don't fire in the background.** The FSM must not rely on
   `Timer` or `Task.sleep` from a suspended app. Slice 17 ships a
   `VirtualClock`-backed scheduler; the real-hardware slice will replace
   the timer source with a `DispatchSourceTimer` held alive by the central
   manager's background mode.

The `UIBackgroundModes` plist key `bluetooth-central` must be set. This
is added alongside the Slice 2 hardware wiring, not here.

## Manual verification (later slice)

Until Slice 2 lights up the CoreBluetooth path there is nothing to verify
on real hardware. Once it does, the manual test plan is:

- [ ] Start a ride, lock the phone, put it in a pocket.
- [ ] Walk out of BLE range for ten seconds.
- [ ] Return to range; confirm dashboard resumes updating within five
      seconds without unlocking the phone.
- [ ] Power-cycle the ESP32 mid-ride; confirm dashboard shows the
      last-known frame with a stale indicator within two seconds and
      fully recovers within five seconds of the ESP32 booting.
- [ ] Toggle Airplane Mode on the phone for thirty seconds; confirm the
      health dot goes red, then green within five seconds of turning it
      back off.

Automation for those scenarios happens in the hardware integration slice.
Until then, the Slice 17 Swift integration test + Unity FSM tests are the
definitive source of truth for the reconnect behavior.
