import Foundation

/// Test-only ``NowPlayingClient`` that holds a scripted response and returns
/// it on every call. The stored response may be `nil` to exercise the
/// "nothing is playing" path.
public final class StaticNowPlayingClient: NowPlayingClient, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: NowPlayingClientResponse?

    public init(response: NowPlayingClientResponse? = nil) {
        self.stored = response
    }

    public func set(_ response: NowPlayingClientResponse?) {
        lock.lock()
        stored = response
        lock.unlock()
    }

    public func fetchNowPlaying() async throws -> NowPlayingClientResponse? {
        return get()
    }

    private func get() -> NowPlayingClientResponse? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
