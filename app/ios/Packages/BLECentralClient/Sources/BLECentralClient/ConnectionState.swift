import Foundation

/// Reason a BLE connection ended. Kept intentionally small — the reconnect
/// FSM only cares about whether the drop was transient (retry) or terminal
/// (stop trying).
public enum DisconnectReason: Sendable, Equatable {
    /// The peer went out of range, power-cycled, or the link layer timed
    /// out. The FSM should attempt to reconnect.
    case linkLost
    /// The user (or the app lifecycle) explicitly asked to disconnect.
    /// The FSM should NOT try to reconnect.
    case userInitiated
    /// Bluetooth was powered off at the OS level. Reconnect only once the
    /// OS reports Bluetooth back on.
    case bluetoothOff
    /// The peer was never paired or pairing was revoked. Terminal.
    case unauthorized
    /// Any other cause — treat as transient.
    case unknown
}

/// State of the BLE central connection, as observed by the rest of the app.
///
/// The values are `Sendable`/`Equatable` so the UI layer can diff them and
/// tests can assert on exact sequences.
public enum ConnectionState: Sendable, Equatable {
    /// No activity. Initial state and also the state after an explicit
    /// `disconnect()`.
    case idle
    /// Actively scanning for the ScramScreen peripheral.
    case scanning
    /// Discovered and dialling.
    case connecting
    /// Link is up; writes will be delivered.
    case connected
    /// Link is down. ``reason`` tells the FSM whether to retry.
    case disconnected(reason: DisconnectReason)
    /// A reconnect attempt is in progress. ``attempt`` starts at 1.
    case reconnecting(attempt: Int)

    /// Whether the app can currently write data to the peer.
    public var canWrite: Bool {
        if case .connected = self { return true }
        return false
    }

    /// Whether the FSM considers this state terminal — i.e. the user asked
    /// to stop or the OS refused.
    public var isTerminal: Bool {
        switch self {
        case .disconnected(.userInitiated), .disconnected(.unauthorized):
            return true
        default:
            return false
        }
    }
}
