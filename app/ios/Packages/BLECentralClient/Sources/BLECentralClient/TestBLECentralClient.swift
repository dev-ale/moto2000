import Foundation

/// Scriptable fake implementation of ``BLECentralClient`` for tests.
///
/// The fake lets tests drive the connection lifecycle with explicit
/// `simulate*` methods and records every byte passed to ``send(_:)``. It
/// never touches real CoreBluetooth, has no timers, and is fully
/// deterministic.
///
/// Example:
/// ```swift
/// let client = TestBLECentralClient()
/// await client.connect()
/// await client.simulateConnected()
/// try await client.send(Data([0x01]))
/// await client.simulateDisconnect(reason: .linkLost)
/// ```
public actor TestBLECentralClient: BLECentralClient {
    /// Writes captured by ``send(_:)``, in order.
    public private(set) var writes: [Data] = []

    /// Number of times ``connect()`` was called.
    public private(set) var connectCallCount: Int = 0

    /// Number of times ``disconnect()`` was called.
    public private(set) var disconnectCallCount: Int = 0

    private var state: ConnectionState = .idle
    private let continuation: AsyncStream<ConnectionState>.Continuation
    private let stream: AsyncStream<ConnectionState>
    private let statusContinuation: AsyncStream<Data>.Continuation
    private let _statusStream: AsyncStream<Data>

    /// If non-nil, the next call to ``send(_:)`` throws this error and
    /// then clears the slot.
    public private(set) var nextSendError: BLECentralClientError?

    /// Queue a one-shot error to be thrown by the next call to ``send(_:)``.
    public func setNextSendError(_ error: BLECentralClientError?) {
        nextSendError = error
    }

    public init() {
        var cont: AsyncStream<ConnectionState>.Continuation!
        self.stream = AsyncStream { cont = $0 }
        self.continuation = cont
        var statusCont: AsyncStream<Data>.Continuation!
        self._statusStream = AsyncStream { statusCont = $0 }
        self.statusContinuation = statusCont
        // Seed the stream with the initial state so late subscribers
        // always see something.
        self.continuation.yield(.idle)
    }

    public nonisolated var stateStream: AsyncStream<ConnectionState> { stream }
    public nonisolated var statusStream: AsyncStream<Data> { _statusStream }

    public func currentState() -> ConnectionState { state }

    public func setPeripheralIdentifier(_ id: UUID?) {
        // No-op in test client.
    }

    public func connect() {
        connectCallCount += 1
        switch state {
        case .connected, .connecting, .scanning, .reconnecting:
            return
        default:
            setState(.scanning)
        }
    }

    public func send(_ bytes: Data) throws {
        if let err = nextSendError {
            nextSendError = nil
            throw err
        }
        guard case .connected = state else {
            throw BLECentralClientError.notConnected
        }
        writes.append(bytes)
    }

    public func disconnect() {
        disconnectCallCount += 1
        setState(.disconnected(reason: .userInitiated))
    }

    // MARK: - Test scripting API

    /// Transition to ``ConnectionState/connecting``.
    public func simulateConnecting() { setState(.connecting) }

    /// Transition to ``ConnectionState/connected``.
    public func simulateConnected() { setState(.connected) }

    /// Simulate a link drop.
    public func simulateDisconnect(reason: DisconnectReason) {
        setState(.disconnected(reason: reason))
    }

    /// Transition to ``ConnectionState/reconnecting(attempt:)``.
    public func simulateReconnecting(attempt: Int) {
        setState(.reconnecting(attempt: attempt))
    }

    /// Force a specific state — useful for edge-case tests.
    public func forceState(_ new: ConnectionState) { setState(new) }

    /// Simulate a status notification arriving from the ESP32.
    public func simulateStatusNotification(_ data: Data) {
        statusContinuation.yield(data)
    }

    private func setState(_ new: ConnectionState) {
        state = new
        continuation.yield(new)
    }
}
