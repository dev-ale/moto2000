import Foundation

public final class MockHeadingProvider: HeadingProvider, @unchecked Sendable {
    private let channel = ProviderChannel<HeadingSample>()
    public let samples: AsyncStream<HeadingSample>

    public init() {
        self.samples = channel.makeStream()
    }

    public func start() async {}
    public func stop() async { channel.finish() }
    public func emit(_ sample: HeadingSample) { channel.emit(sample) }
}
