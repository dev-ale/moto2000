import XCTest
import RideSimulatorKit

@testable import ScramCore

final class RouteCollectorTests: XCTestCase {

    // MARK: - Stationary points filtered

    func test_stationaryPoints_areFiltered() async {
        let provider = MockStreamProvider()
        let collector = RouteCollector()
        collector.start(provider: provider)

        // Emit stationary points (speed < 1 m/s)
        provider.emit(sample(lat: 47.56, lon: 7.59, speed: 0.0))
        provider.emit(sample(lat: 47.57, lon: 7.60, speed: 0.5))
        provider.emit(sample(lat: 47.58, lon: 7.61, speed: 0.99))

        // Give the async stream time to deliver
        try? await Task.sleep(nanoseconds: 100_000_000)

        let points = collector.stop()
        XCTAssertTrue(points.isEmpty, "Stationary points should be filtered out")
    }

    // MARK: - Nearby points deduplicated

    func test_nearbyPoints_areDeduplicated() async {
        let provider = MockStreamProvider()
        let collector = RouteCollector()
        collector.start(provider: provider)

        // Emit a moving point
        provider.emit(sample(lat: 47.560000, lon: 7.590000, speed: 10.0))
        // Emit a point very close (< 10m away)
        provider.emit(sample(lat: 47.560001, lon: 7.590001, speed: 10.0))
        // Another very close point
        provider.emit(sample(lat: 47.560002, lon: 7.590002, speed: 10.0))

        try? await Task.sleep(nanoseconds: 100_000_000)

        let points = collector.stop()
        XCTAssertEqual(points.count, 1, "Nearby points should be deduplicated")
    }

    // MARK: - Moving points collected

    func test_movingPoints_areCollected() async {
        let provider = MockStreamProvider()
        let collector = RouteCollector()
        collector.start(provider: provider)

        // Emit points that are far apart and moving
        provider.emit(sample(lat: 47.560, lon: 7.590, speed: 15.0))
        provider.emit(sample(lat: 47.562, lon: 7.592, speed: 15.0))
        provider.emit(sample(lat: 47.564, lon: 7.594, speed: 15.0))

        try? await Task.sleep(nanoseconds: 100_000_000)

        let points = collector.stop()
        XCTAssertEqual(points.count, 3, "Moving, distant points should all be collected")
        XCTAssertEqual(points[0].latitude, 47.560, accuracy: 0.0001)
        XCTAssertEqual(points[2].latitude, 47.564, accuracy: 0.0001)
    }

    // MARK: - Mixed samples

    func test_mixedSamples_onlyMovingAndDistantKept() async {
        let provider = MockStreamProvider()
        let collector = RouteCollector()
        collector.start(provider: provider)

        // Moving, first point
        provider.emit(sample(lat: 47.560, lon: 7.590, speed: 10.0))
        // Stationary, should be filtered
        provider.emit(sample(lat: 47.570, lon: 7.600, speed: 0.5))
        // Moving but too close to first, should be deduplicated
        provider.emit(sample(lat: 47.560001, lon: 7.590001, speed: 10.0))
        // Moving and far enough
        provider.emit(sample(lat: 47.562, lon: 7.592, speed: 10.0))

        try? await Task.sleep(nanoseconds: 100_000_000)

        let points = collector.stop()
        XCTAssertEqual(points.count, 2)
    }

    // MARK: - Helpers

    private func sample(lat: Double, lon: Double, speed: Double) -> LocationSample {
        LocationSample(
            scenarioTime: 0,
            latitude: lat,
            longitude: lon,
            altitudeMeters: 0,
            speedMps: speed,
            courseDegrees: 0,
            horizontalAccuracyMeters: 5
        )
    }
}

// MARK: - Mock provider

/// A simple mock that lets tests push samples into an AsyncStream.
private final class MockStreamProvider: LocationProvider, @unchecked Sendable {
    private let continuation: AsyncStream<LocationSample>.Continuation
    let samples: AsyncStream<LocationSample>

    init() {
        var cont: AsyncStream<LocationSample>.Continuation!
        samples = AsyncStream { continuation in
            cont = continuation
        }
        continuation = cont
    }

    func emit(_ sample: LocationSample) {
        continuation.yield(sample)
    }

    func start() async {}
    func stop() async {
        continuation.finish()
    }
}
