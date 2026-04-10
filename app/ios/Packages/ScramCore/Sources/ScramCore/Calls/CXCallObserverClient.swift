import Foundation

#if canImport(CallKit) && os(iOS)
import CallKit

/// Production ``CallKitClient`` backed by `CXCallObserver`.
///
/// Uses `CXCallObserverDelegate` to track live call state changes and
/// returns the current state when polled via ``fetchCallState()``.
///
/// **Apple restriction:** `CXCallObserver` does NOT expose the caller's
/// name or phone number to third-party apps. The `callerHandle` field
/// is always set to "Eingehender Anruf" for incoming/connected calls.
public final class CXCallObserverClient: NSObject, CallKitClient, CXCallObserverDelegate, @unchecked Sendable {
    private let observer: CXCallObserver
    private let lock = NSLock()
    private var latestCall: CXCall?

    public override init() {
        self.observer = CXCallObserver()
        super.init()
        observer.setDelegate(self, queue: nil)
    }

    // MARK: - CallKitClient

    public func fetchCallState() async throws -> CallKitClientResponse? {
        let call = lock.withLock { latestCall }

        // Also check the observer's current calls in case the delegate
        // hasn't fired yet (e.g. a call was already in progress at launch).
        let activeCalls = observer.calls
        let target = call ?? activeCalls.first

        guard let target else { return nil }

        // A call that has ended is no longer useful after we report it once.
        if target.hasEnded {
            lock.withLock {
                if latestCall?.uuid == target.uuid {
                    latestCall = nil
                }
            }
            return CallKitClientResponse(
                state: .ended,
                callerHandle: ""
            )
        }

        if target.hasConnected {
            return CallKitClientResponse(
                state: .connected,
                callerHandle: "Eingehender Anruf"
            )
        }

        if !target.isOutgoing {
            return CallKitClientResponse(
                state: .incoming,
                callerHandle: "Eingehender Anruf"
            )
        }

        // Outgoing call that hasn't connected yet — not relevant for alerts.
        return nil
    }

    // MARK: - CXCallObserverDelegate

    public func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        lock.lock()
        latestCall = call
        lock.unlock()
    }
}
#else

/// Non-iOS platforms never have CallKit; the type exists only so code
/// that references it compiles on macOS unit tests.
public final class CXCallObserverClient: CallKitClient, @unchecked Sendable {
    public init() {}

    public func fetchCallState() async throws -> CallKitClientResponse? {
        throw CallKitClientError.notImplemented
    }
}
#endif
