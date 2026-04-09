import Foundation

public final class MockMotionProvider: MotionProvider, @unchecked Sendable {
    private let channel = ProviderChannel<MotionSample>()
    public let samples: AsyncStream<MotionSample>

    public init() {
        self.samples = channel.makeStream()
    }

    public func start() async {}
    public func stop() async { channel.finish() }
    public func emit(_ sample: MotionSample) { channel.emit(sample) }
}
