import Foundation

/// External events fed into ``ReconnectStateMachine``.
public enum ReconnectEvent: Sendable, Equatable {
    /// The link came up (either the first connection or a successful
    /// reconnect).
    case didConnect
    /// The link dropped. The `reason` determines whether the FSM starts a
    /// reconnect loop or gives up.
    case didDisconnect(reason: DisconnectReason)
    /// A previously scheduled backoff timer fired.
    case reconnectTick
    /// The app explicitly asked to start connecting (e.g. user toggled the
    /// device on).
    case startRequested
    /// The app explicitly asked to stop (e.g. user toggled the device off).
    case stopRequested
}

/// Side effects the FSM asks its owner to perform. The owner decides HOW;
/// the FSM decides WHEN.
public enum ReconnectAction: Sendable, Equatable {
    /// Begin scanning for the peer.
    case startScan
    /// Ask the central to (re-)attempt a connection.
    case attemptConnect
    /// Arm a one-shot timer for `delaySeconds` that will deliver a
    /// ``ReconnectEvent/reconnectTick`` when it fires.
    case scheduleNextAttempt(delaySeconds: Double)
    /// Stop all reconnect activity — the state is terminal.
    case cancelAll
    /// Nothing to do.
    case none
}

/// Pure state machine that governs BLE reconnect behavior.
///
/// The FSM itself owns no timers and no BLE handles. It is driven by its
/// owner calling ``handle(_:)`` with events, and responds with a
/// ``ReconnectAction``. This design keeps every transition unit-testable
/// without any concurrency, timer, or Bluetooth machinery — drive it with
/// scripted events and a ``VirtualClock`` from `RideSimulatorKit`.
///
/// ## Backoff schedule
///
/// The delays between reconnect attempts form a capped exponential ramp:
///
/// | Attempt | Delay (ms) |
/// |---------|------------|
/// | 1       | 100        |
/// | 2       | 200        |
/// | 3       | 400        |
/// | 4       | 800        |
/// | 5       | 1600       |
/// | 6+      | 3000 (cap) |
///
/// The first five attempts fit inside ~3.1 s, which keeps the total worst
/// case for a successful reconnect well under the 5 s requirement in Slice
/// 17: 100 + 200 + 400 + 800 + 1600 = 3 100 ms of waiting before attempt 5,
/// which then itself has the usual ~400 ms round trip. The FSM reports its
/// worst-case budget via ``worstCaseReconnectLatencySeconds`` so tests can
/// assert on it.
public actor ReconnectStateMachine {
    /// Backoff delays in milliseconds, indexed by attempt number (1-based).
    /// Any attempt beyond the last index uses the final value.
    public static let backoffSchedule: [Int] = [100, 200, 400, 800, 1600, 3000]

    /// Sum of the first five delays, in seconds. This is the worst-case
    /// wall-clock wait before the FSM commits to its fifth attempt — by
    /// design it sits below the 5 s target.
    public static let worstCaseReconnectLatencySeconds: Double = 3.1

    public private(set) var state: ConnectionState = .idle

    /// Number of consecutive reconnect attempts made since the last
    /// successful connection. Reset on ``ReconnectEvent/didConnect``.
    public private(set) var attemptCount: Int = 0

    /// Monotonic tick of how many backoff delays have been issued. Used by
    /// tests to assert on the exact schedule.
    public private(set) var scheduledDelays: [Double] = []

    public init() {}

    /// Feed one event into the FSM and get back the action the owner must
    /// take. Pure: the FSM mutates only its own state.
    public func handle(_ event: ReconnectEvent) -> ReconnectAction {
        switch event {
        case .startRequested:
            return onStartRequested()
        case .stopRequested:
            return onStopRequested()
        case .didConnect:
            return onDidConnect()
        case .didDisconnect(let reason):
            return onDidDisconnect(reason: reason)
        case .reconnectTick:
            return onReconnectTick()
        }
    }

    /// Delay (in seconds) for the given attempt number, clamped to the
    /// last entry in ``backoffSchedule``.
    public static func backoffSeconds(forAttempt attempt: Int) -> Double {
        let clamped = max(1, attempt)
        let index = min(clamped - 1, backoffSchedule.count - 1)
        return Double(backoffSchedule[index]) / 1000.0
    }

    // MARK: - Transitions

    private func onStartRequested() -> ReconnectAction {
        switch state {
        case .idle, .disconnected:
            state = .scanning
            attemptCount = 0
            return .startScan
        case .scanning, .connecting, .connected, .reconnecting:
            return .none
        }
    }

    private func onStopRequested() -> ReconnectAction {
        state = .disconnected(reason: .userInitiated)
        attemptCount = 0
        return .cancelAll
    }

    private func onDidConnect() -> ReconnectAction {
        state = .connected
        attemptCount = 0
        return .none
    }

    private func onDidDisconnect(reason: DisconnectReason) -> ReconnectAction {
        switch reason {
        case .userInitiated, .unauthorized:
            state = .disconnected(reason: reason)
            attemptCount = 0
            return .cancelAll
        case .bluetoothOff:
            // Stop trying until the OS tells us BT came back. Treated as
            // terminal from the FSM's point of view — a higher layer
            // restarts via `.startRequested` on the `poweredOn` callback.
            state = .disconnected(reason: reason)
            attemptCount = 0
            return .cancelAll
        case .linkLost, .unknown:
            attemptCount = 1
            state = .reconnecting(attempt: attemptCount)
            let delay = Self.backoffSeconds(forAttempt: attemptCount)
            scheduledDelays.append(delay)
            return .scheduleNextAttempt(delaySeconds: delay)
        }
    }

    private func onReconnectTick() -> ReconnectAction {
        // Guard: only relevant while reconnecting.
        guard case .reconnecting = state else { return .none }
        return .attemptConnect
    }

    /// Signals that an in-flight reconnect attempt failed. The FSM bumps
    /// the attempt counter and schedules the next backoff slot.
    public func attemptFailed() -> ReconnectAction {
        guard case .reconnecting = state else { return .none }
        attemptCount += 1
        state = .reconnecting(attempt: attemptCount)
        let delay = Self.backoffSeconds(forAttempt: attemptCount)
        scheduledDelays.append(delay)
        return .scheduleNextAttempt(delaySeconds: delay)
    }
}
