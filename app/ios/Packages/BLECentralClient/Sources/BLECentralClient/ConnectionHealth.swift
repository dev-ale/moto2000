import Foundation

/// Visual bucket for the connection health dot in the UI.
public enum ConnectionHealthLevel: Sendable, Equatable {
    /// Connected and recent traffic. Dot = green.
    case good
    /// Connected but no traffic in a while, or mid-reconnect. Dot =
    /// yellow.
    case degraded
    /// Disconnected. Dot = red.
    case down
}

/// Snapshot of connection health consumed by the UI.
///
/// `secondsSinceLastWrite` is `nil` if no write has ever succeeded. The UI
/// layer renders a dot based on ``level`` and can render a tooltip using
/// the raw number.
public struct ConnectionHealth: Sendable, Equatable {
    public let state: ConnectionState
    public let secondsSinceLastWrite: Double?
    public let level: ConnectionHealthLevel

    public init(state: ConnectionState, secondsSinceLastWrite: Double?, level: ConnectionHealthLevel) {
        self.state = state
        self.secondsSinceLastWrite = secondsSinceLastWrite
        self.level = level
    }
}

/// Actor that tracks connection state and the time of the last successful
/// write, then publishes ``ConnectionHealth`` snapshots.
///
/// The monitor is clock-agnostic: callers pass a `now` timestamp to every
/// mutation, matching the rest of the package, so tests can drive it with
/// ``RideSimulatorKit/VirtualClock``.
public actor ConnectionHealthMonitor {
    /// How many seconds can pass after a successful write before a
    /// still-connected link counts as `.degraded`.
    public let degradedAfterSeconds: Double

    private var currentState: ConnectionState = .idle
    private var lastWriteAt: Double?

    public init(degradedAfterSeconds: Double = 2.0) {
        self.degradedAfterSeconds = degradedAfterSeconds
    }

    public func updateState(_ state: ConnectionState) {
        currentState = state
    }

    public func recordSuccessfulWrite(at now: Double) {
        lastWriteAt = now
    }

    public func snapshot(at now: Double) -> ConnectionHealth {
        let secs: Double? = lastWriteAt.map { now - $0 }
        let level: ConnectionHealthLevel
        switch currentState {
        case .connected:
            if let s = secs, s <= degradedAfterSeconds {
                level = .good
            } else {
                level = .degraded
            }
        case .scanning, .connecting, .reconnecting:
            level = .degraded
        case .idle, .disconnected:
            level = .down
        }
        return ConnectionHealth(state: currentState, secondsSinceLastWrite: secs, level: level)
    }
}
