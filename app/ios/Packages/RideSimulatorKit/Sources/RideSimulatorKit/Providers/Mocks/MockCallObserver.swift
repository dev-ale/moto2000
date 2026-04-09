import Foundation

public final class MockCallObserver: CallObserver, @unchecked Sendable {
    private let channel = ProviderChannel<CallEvent>()
    public let events: AsyncStream<CallEvent>

    public init() {
        self.events = channel.makeStream()
    }

    public func start() async {}
    public func stop() async { channel.finish() }
    public func emit(_ event: CallEvent) { channel.emit(event) }
}
