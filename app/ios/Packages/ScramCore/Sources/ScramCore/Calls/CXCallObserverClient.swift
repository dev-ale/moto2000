import Foundation

#if canImport(CallKit)
import CallKit

/// iOS-only stub for ``CallKitClient`` backed by `CXCallObserver`.
///
/// # Why is this a stub?
///
/// `CXCallObserver` provides only call state transitions (incoming,
/// connected, ended, on hold) — it does NOT expose the caller's name
/// or phone number to third-party apps. The `callerHandle` field of
/// ``CallKitClientResponse`` is therefore always "unknown" when using
/// the real system observer. See docs/platform-limits.md.
///
/// Slice 13 ships the ``CallKitClient`` protocol seam so the rest of
/// the domain (``RealCallObserver``, ``CallAlertService``, the BLE
/// pipeline) can be fully tested today. A follow-up slice may wire
/// real `CXCallObserver` state transitions.
public final class CXCallObserverClient: CallKitClient, @unchecked Sendable {
    public init() {}

    public func fetchCallState() async throws -> CallKitClientResponse? {
        throw CallKitClientError.notImplemented
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
