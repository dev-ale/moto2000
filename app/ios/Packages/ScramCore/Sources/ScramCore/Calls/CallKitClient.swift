import Foundation

/// Abstracts "where does the current call state come from" so the rest of
/// the iOS domain never touches `CXCallObserver` (or any other system
/// framework) directly.
///
/// Tests inject ``StaticCallKitClient``; production code eventually
/// injects ``CXCallObserverClient`` (gated on CallKit availability).
public protocol CallKitClient: Sendable {
    /// Fetches the current call state, or `nil` if no call is in progress.
    func fetchCallState() async throws -> CallKitClientResponse?
}

/// Decoupled value type returned by ``CallKitClient`` implementations.
public struct CallKitClientResponse: Sendable, Equatable {
    public enum State: String, Sendable, Equatable {
        case incoming
        case connected
        case ended
    }

    public var state: State
    public var callerHandle: String

    public init(state: State, callerHandle: String) {
        self.state = state
        self.callerHandle = callerHandle
    }
}

public enum CallKitClientError: Error, Sendable, Equatable {
    /// The client is a deferred stub — Slice 13 ships the protocol seam but
    /// CXCallObserver only exposes call state, not caller name/number.
    /// See docs/platform-limits.md.
    case notImplemented
    /// The system denied access to call state.
    case permissionDenied
}
