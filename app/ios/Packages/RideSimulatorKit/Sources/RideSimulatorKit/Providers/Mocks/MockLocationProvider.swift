import Foundation

/// Scenario-driven ``LocationProvider``.
///
/// The provider holds a reference to its channel; the ``ScenarioPlayer``
/// pushes samples in over time, and any consumer awaiting the
/// ``samples`` stream sees them. Exposed publicly so tests can instantiate
/// it directly without spinning up a full player.
public final class MockLocationProvider: LocationProvider, @unchecked Sendable {
    private let channel = ProviderChannel<LocationSample>()
    public let samples: AsyncStream<LocationSample>

    public init() {
        self.samples = channel.makeStream()
    }

    public func start() async {}
    public func stop() async { channel.finish() }

    /// Emit a sample into the stream. Used by the player and by tests.
    public func emit(_ sample: LocationSample) {
        channel.emit(sample)
    }
}
