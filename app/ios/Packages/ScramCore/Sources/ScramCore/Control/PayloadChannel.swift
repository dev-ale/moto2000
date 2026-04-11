import Foundation

/// Thread-safe single-producer broadcaster for encoded BLE payloads.
///
/// Each service creates its own instance — lifecycles stay independent.
/// This is the single shared definition; all previous duplications
/// (`PayloadChannelHelper`, `TripStatsPayloadChannel`, etc.) are deleted.
public final class PayloadChannel: @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    private let lock = NSLock()

    public init() {}

    public func makeStream() -> AsyncStream<Data> {
        AsyncStream<Data>(bufferingPolicy: .unbounded) { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    public func emit(_ element: Data) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(element)
    }

    public func finish() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.finish()
    }
}
