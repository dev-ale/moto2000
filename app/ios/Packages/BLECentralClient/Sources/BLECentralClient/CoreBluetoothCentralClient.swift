import Foundation

/// Production ``BLECentralClient`` backed by CoreBluetooth.
///
/// The actual `CBCentralManager` scanning / discovery / write logic lands in
/// Slice 2 (#3) once real hardware is available. This type exists today so
/// the rest of the app — the reconnect FSM, the last-known cache, and the
/// connection health publisher — can compile and be unit tested end-to-end
/// against the ``BLECentralClient`` protocol.
///
/// Every method here is a no-op that transitions the state machine exactly
/// the way the real implementation will once filled in, so that higher
/// layers can start integrating immediately.
public actor CoreBluetoothCentralClient: BLECentralClient {
    private var state: ConnectionState = .idle
    private let continuation: AsyncStream<ConnectionState>.Continuation
    private let stream: AsyncStream<ConnectionState>

    public init() {
        var cont: AsyncStream<ConnectionState>.Continuation!
        self.stream = AsyncStream { cont = $0 }
        self.continuation = cont
        self.continuation.yield(.idle)
    }

    public nonisolated var stateStream: AsyncStream<ConnectionState> { stream }

    public func currentState() -> ConnectionState { state }

    public func connect() {
        // Real wiring lives in Slice 2. Leaving the transition here so the
        // FSM can observe a deterministic state change during dry runs.
        guard case .idle = state else { return }
        setState(.scanning)
    }

    public func send(_ bytes: Data) throws {
        // Intentionally unused on stub path — parameter acknowledged to
        // silence `-Wunused`.
        _ = bytes
        guard case .connected = state else {
            throw BLECentralClientError.notConnected
        }
        // Real write goes here in Slice 2.
    }

    public func disconnect() {
        setState(.disconnected(reason: .userInitiated))
    }

    private func setState(_ new: ConnectionState) {
        state = new
        continuation.yield(new)
    }
}
