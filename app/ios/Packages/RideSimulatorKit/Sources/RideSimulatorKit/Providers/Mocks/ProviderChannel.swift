import Foundation

/// A single-producer, single-consumer broadcaster used by every mock
/// provider to deliver timestamped events to an ``AsyncStream``.
///
/// Callers construct the stream via ``makeStream()`` once and then emit
/// events via ``emit(_:)``. Calling ``finish()`` ends the stream; it is
/// idempotent. If no consumer is attached, events are dropped silently,
/// which matches `AsyncStream.Continuation`'s default buffering policy
/// of `.bufferingNewest(1)` we use below.
final class ProviderChannel<Element: Sendable>: @unchecked Sendable {
    private var continuation: AsyncStream<Element>.Continuation?
    private let lock = NSLock()

    func makeStream() -> AsyncStream<Element> {
        AsyncStream<Element>(bufferingPolicy: .unbounded) { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func emit(_ element: Element) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(element)
    }

    func finish() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.finish()
    }
}
