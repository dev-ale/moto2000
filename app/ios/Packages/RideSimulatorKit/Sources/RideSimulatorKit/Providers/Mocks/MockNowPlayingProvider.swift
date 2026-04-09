import Foundation

public final class MockNowPlayingProvider: NowPlayingProvider, @unchecked Sendable {
    private let channel = ProviderChannel<NowPlayingSnapshot>()
    public let snapshots: AsyncStream<NowPlayingSnapshot>

    public init() {
        self.snapshots = channel.makeStream()
    }

    public func start() async {}
    public func stop() async { channel.finish() }
    public func emit(_ snapshot: NowPlayingSnapshot) { channel.emit(snapshot) }
}
