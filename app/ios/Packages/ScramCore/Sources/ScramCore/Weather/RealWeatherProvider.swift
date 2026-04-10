import Foundation
import RideSimulatorKit

/// Real (non-simulator) ``WeatherProvider`` that polls a
/// ``WeatherServiceClient`` on a refresh interval driven by a
/// ``SimulatedClock``.
///
/// The provider emits ``WeatherSnapshot`` values on its ``snapshots`` stream.
/// Errors from the upstream client are swallowed after being logged so the
/// loop keeps going (e.g. a transient network blip should not stop weather
/// updates forever); in practice the Slice 7 stub throws
/// ``WeatherServiceError/notImplemented`` on every call and the provider
/// simply never emits anything, which is the intended "deferred" behaviour.
///
/// A ``SimulatedClock`` is injected so tests can drive the refresh loop
/// with a ``VirtualClock``; production code passes a ``WallClock``.
public final class RealWeatherProvider: WeatherProvider, @unchecked Sendable {
    public struct Coordinate: Sendable, Equatable {
        public var latitude: Double
        public var longitude: Double
        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    private let client: any WeatherServiceClient
    private let clock: any SimulatedClock
    private let coordinate: Coordinate
    private let refreshInterval: Double
    private let channel = WeatherChannel()
    public let snapshots: AsyncStream<WeatherSnapshot>

    private var pollingTask: Task<Void, Never>?

    public init(
        client: any WeatherServiceClient,
        clock: any SimulatedClock,
        coordinate: Coordinate,
        refreshInterval: Double = 60.0
    ) {
        self.client = client
        self.clock = clock
        self.coordinate = coordinate
        self.refreshInterval = refreshInterval
        self.snapshots = channel.makeStream()
    }

    public func start() async {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
        channel.finish()
    }

    // MARK: - Poll loop

    private func pollLoop() async {
        var nextWakeAt = await clock.nowSeconds
        while !Task.isCancelled {
            await fetchOnce()
            nextWakeAt += refreshInterval
            do {
                try await clock.sleep(until: nextWakeAt)
            } catch {
                return
            }
        }
    }

    private func fetchOnce() async {
        let now = await clock.nowSeconds
        do {
            let response = try await client.fetchCurrentWeather(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            let snapshot = WeatherSnapshot(
                scenarioTime: now,
                condition: response.condition,
                temperatureCelsius: response.temperatureCelsius,
                highCelsius: response.highCelsius,
                lowCelsius: response.lowCelsius,
                locationName: response.locationName
            )
            channel.emit(snapshot)
        } catch {
            // Intentionally swallowed. See class doc comment.
        }
    }
}

/// Single-producer broadcaster for ``WeatherSnapshot`` values.
///
/// Mirrors ``LocationChannel`` and ``PayloadChannel``; lifted into its own
/// type because ``RealWeatherProvider`` owns a dedicated stream for the
/// downstream ``WeatherService``.
final class WeatherChannel: @unchecked Sendable {
    private var continuation: AsyncStream<WeatherSnapshot>.Continuation?
    private let lock = NSLock()

    func makeStream() -> AsyncStream<WeatherSnapshot> {
        AsyncStream<WeatherSnapshot>(bufferingPolicy: .unbounded) { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func emit(_ element: WeatherSnapshot) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(element)
    }

    func finish() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.finish()
    }
}
