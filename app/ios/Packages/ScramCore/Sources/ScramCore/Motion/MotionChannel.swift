import Foundation
import RideSimulatorKit

/// Single-producer broadcaster used by ``RealMotionProvider`` to deliver
/// ``MotionSample`` values into an ``AsyncStream``. Mirrors
/// ``LocationChannel`` and the internal `ProviderChannel` used by
/// RideSimulatorKit's mocks.
final class MotionChannel: @unchecked Sendable {
    private var continuation: AsyncStream<MotionSample>.Continuation?
    private let lock = NSLock()

    func makeStream() -> AsyncStream<MotionSample> {
        AsyncStream<MotionSample>(bufferingPolicy: .unbounded) { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func emit(_ element: MotionSample) {
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
