import Foundation

public final class MockWeatherProvider: WeatherProvider, @unchecked Sendable {
    private let channel = ProviderChannel<WeatherSnapshot>()
    public let snapshots: AsyncStream<WeatherSnapshot>

    public init() {
        self.snapshots = channel.makeStream()
    }

    public func start() async {}
    public func stop() async { channel.finish() }
    public func emit(_ snapshot: WeatherSnapshot) { channel.emit(snapshot) }
}
