import Foundation
import RideSimulatorKit

/// Single-producer broadcaster used by ``RealLocationProvider`` to deliver
/// ``LocationSample`` values to its ``AsyncStream``.
///
/// Mirrors the internal `ProviderChannel` used by RideSimulatorKit's mock
/// providers, copied here because that helper is not exposed publicly.
/// If a second real provider ever needs the same pattern, promote this to a
/// shared utility.
final class LocationChannel: @unchecked Sendable {
    private var continuation: AsyncStream<LocationSample>.Continuation?
    private let lock = NSLock()

    func makeStream() -> AsyncStream<LocationSample> {
        AsyncStream<LocationSample>(bufferingPolicy: .unbounded) { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func emit(_ element: LocationSample) {
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
