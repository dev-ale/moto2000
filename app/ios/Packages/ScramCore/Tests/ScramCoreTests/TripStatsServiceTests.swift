import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class TripStatsServiceTests: XCTestCase {
    func test_ingest_emitsOnePayloadPerSample() async throws {
        let mock = MockLocationProvider()
        let service = TripStatsService(provider: mock)
        service.start()

        var iterator = service.payloads.makeAsyncIterator()

        mock.emit(
            LocationSample(scenarioTime: 0, latitude: 47.0, longitude: 7.0, altitudeMeters: 260, speedMps: 0)
        )
        mock.emit(
            LocationSample(scenarioTime: 1, latitude: 47.0001, longitude: 7.0, altitudeMeters: 260, speedMps: 11)
        )

        let first = await iterator.next()
        let second = await iterator.next()
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)

        // Decode the second payload — it should reflect the accumulated state.
        guard let second, case .tripStats(let stats, _) = try? ScreenPayloadCodec.decode(second) else {
            XCTFail("expected tripStats payload")
            return
        }
        XCTAssertEqual(stats.rideTimeSeconds, 1)
        XCTAssertGreaterThan(stats.distanceMeters, 0)
        XCTAssertGreaterThan(stats.maxSpeedKmhX10, 0)

        service.stop()
    }

    func test_reset_returnsAccumulatorToZeros() async throws {
        let mock = MockLocationProvider()
        let service = TripStatsService(provider: mock)
        service.start()

        var iterator = service.payloads.makeAsyncIterator()

        mock.emit(LocationSample(scenarioTime: 0, latitude: 47, longitude: 7, altitudeMeters: 260, speedMps: 5))
        mock.emit(LocationSample(scenarioTime: 5, latitude: 47.001, longitude: 7, altitudeMeters: 260, speedMps: 5))
        _ = await iterator.next()
        _ = await iterator.next()

        // Spot-check non-zero state then reset.
        let snapBefore = service.currentSnapshot
        XCTAssertGreaterThan(snapBefore.rideTimeSeconds, 0)
        service.reset()
        let snapAfter = service.currentSnapshot
        XCTAssertEqual(snapAfter.rideTimeSeconds, 0)
        XCTAssertEqual(snapAfter.distanceMeters, 0)
        XCTAssertEqual(snapAfter.maxSpeedKmhX10, 0)

        // After reset the next sample should re-seed lastSample. The
        // *following* sample then begins accumulating from there.
        mock.emit(LocationSample(scenarioTime: 100, latitude: 48, longitude: 7, altitudeMeters: 260, speedMps: 0))
        _ = await iterator.next()
        let afterSeed = service.currentSnapshot
        XCTAssertEqual(afterSeed.rideTimeSeconds, 0)

        mock.emit(LocationSample(scenarioTime: 101, latitude: 48.0001, longitude: 7, altitudeMeters: 260, speedMps: 5))
        _ = await iterator.next()
        let afterSecond = service.currentSnapshot
        XCTAssertEqual(afterSecond.rideTimeSeconds, 1)
        XCTAssertGreaterThan(afterSecond.distanceMeters, 0)

        service.stop()
    }

    func test_doubleStart_isIdempotent() {
        let mock = MockLocationProvider()
        let service = TripStatsService(provider: mock)
        service.start()
        service.start() // must not crash, must not spawn a second task
        service.stop()
    }
}
