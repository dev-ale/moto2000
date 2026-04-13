import Foundation

extension BLECentralClient {
    public func sendControl(_ bytes: Data) async throws {
        throw BLECentralClientError.notConnected
    }
    public func sendOTA(_ bytes: Data) async throws {
        throw BLECentralClientError.notConnected
    }
}

/// Errors surfaced by a ``BLECentralClient``.
public enum BLECentralClientError: Error, Equatable, Sendable {
    /// Caller tried to ``BLECentralClient/send(_:)`` while not connected.
    case notConnected
    /// The underlying transport reported a write failure. The `message`
    /// field is for logging; decisions should not branch on it.
    case writeFailed(message: String)
    /// Bluetooth radio is powered off at the OS level.
    case bluetoothOff
}

/// Abstraction over a BLE central that owns one peer (the ScramScreen).
///
/// Production code binds this to a `CBCentralManager` wrapper
/// (``CoreBluetoothCentralClient``); tests bind it to
/// ``TestBLECentralClient`` to script scenarios deterministically.
///
/// Implementations must be actor-isolated or otherwise thread-safe — the
/// reconnect FSM calls into them from an actor context.
public protocol BLECentralClient: Sendable {
    /// An async sequence of state changes. A fresh subscriber receives the
    /// current state as its first element and then every subsequent change.
    ///
    /// The stream is expected to finish only when the client itself is
    /// torn down.
    var stateStream: AsyncStream<ConnectionState> { get }

    /// An async sequence of raw status notifications from the ESP32
    /// (`status` characteristic). Each element is the raw bytes of one
    /// notification; callers decode with ``StatusMessage.decode(_:)``.
    ///
    /// The stream finishes when the client is torn down.
    var statusStream: AsyncStream<Data> { get }

    /// Current state, sampled synchronously. Mostly for tests and UI hot
    /// paths where awaiting the stream is awkward.
    func currentState() async -> ConnectionState

    /// Set the Bluetooth peripheral identifier (from AccessorySetupKit)
    /// so reconnection uses direct retrieval instead of scanning.
    func setPeripheralIdentifier(_ id: UUID?) async

    /// Begin scanning and connect to the first matching peripheral.
    ///
    /// Idempotent: calling ``connect()`` while already connected or
    /// connecting is a no-op.
    func connect() async

    /// Write one payload to the peer. Throws ``BLECentralClientError/notConnected``
    /// if the link is down — callers should buffer in the
    /// ``LastKnownPayloadCache`` rather than treat this as fatal.
    func send(_ bytes: Data) async throws

    /// Write a 4-byte control command to the dedicated `control`
    /// characteristic (e.g. `SET_BRIGHTNESS`, `SET_ACTIVE_SCREEN`).
    /// Default implementation throws notConnected so existing test
    /// doubles don't have to implement it.
    func sendControl(_ bytes: Data) async throws

    /// Write one OTA frame to the `ota_data` characteristic. Frames
    /// are interpreted by the firmware-side `ota_receiver`. The first
    /// byte of `bytes` must be a frame type (BEGIN/CHUNK/COMMIT/ABORT).
    /// Default implementation throws notConnected so existing test
    /// doubles don't have to implement it.
    func sendOTA(_ bytes: Data) async throws

    /// Tear the link down deliberately. The resulting state is
    /// ``ConnectionState/disconnected(reason:)`` with
    /// ``DisconnectReason/userInitiated`` so the reconnect FSM leaves it
    /// alone.
    func disconnect() async
}
