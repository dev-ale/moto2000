import Foundation

/// Test-only ``CallKitClient`` that holds a scripted response and returns
/// it on every call. The stored response may be `nil` to exercise the
/// "no call in progress" path.
public final class StaticCallKitClient: CallKitClient, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CallKitClientResponse?

    public init(response: CallKitClientResponse? = nil) {
        self.stored = response
    }

    public func set(_ response: CallKitClientResponse?) {
        lock.lock()
        stored = response
        lock.unlock()
    }

    public func fetchCallState() async throws -> CallKitClientResponse? {
        return get()
    }

    private func get() -> CallKitClientResponse? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
