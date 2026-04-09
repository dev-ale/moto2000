import Foundation

/// A transport that carries ScramScreen BLE payloads from the iOS app to
/// "something that renders them". The same `send(_:)` call will later be
/// implemented against a real Core Bluetooth peripheral (Slice 2); for now
/// it has two loopback implementations that keep the develop-without-a-bike
/// workflow end-to-end.
///
/// Why an abstraction at all: the whole point of Slice 1.5b is to let the
/// scenario player drive the **firmware-side** renderer (the host
/// simulator) over the *same* codec as the real device. Hiding the wire
/// behind a protocol means the switch from "stdin pipe" today to "GATT
/// write" tomorrow is one dependency injection away.
public protocol BLETransport: Sendable {
    /// Deliver one fully-encoded BLE payload — the exact bytes a BLE peer
    /// would write to the firmware characteristic, including the 8-byte
    /// header.
    func send(_ payload: Data) async throws
}

/// A transport that silently discards every payload. Useful as a default
/// in tests, in Release builds before Slice 2 wires a real peripheral,
/// and in any call site that wants to exercise encoding without side
/// effects.
public struct NullBLETransport: BLETransport {
    public init() {}
    public func send(_ payload: Data) async throws {
        // Intentionally empty. The payload was already encoded; that is
        // what we wanted to exercise.
        _ = payload
    }
}

/// Errors raised by the host-simulator loopback transport.
public enum HostSimulatorTransportError: Error, Equatable, Sendable {
    /// The configured simulator executable does not exist on disk.
    case simulatorNotFound(path: String)
    /// The simulator exited with a non-zero status.
    case simulatorFailed(status: Int32, stderr: String)
    /// The simulator is only available on desktop OSes (macOS + Linux).
    case unsupportedPlatform
}
