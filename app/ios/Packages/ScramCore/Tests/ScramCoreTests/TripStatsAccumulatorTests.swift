import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class TripStatsAccumulatorTests: XCTestCase {
    func test_emptyAccumulator_isAllZeros() {
        let acc = TripStatsAccumulator()
        let snap = acc.snapshot
        XCTAssertEqual(snap.rideTimeSeconds, 0)
        XCTAssertEqual(snap.distanceMeters, 0)
        XCTAssertEqual(snap.averageSpeedKmhX10, 0)
        XCTAssertEqual(snap.maxSpeedKmhX10, 0)
        XCTAssertEqual(snap.ascentMeters, 0)
        XCTAssertEqual(snap.descentMeters, 0)
    }

    func test_singleSample_seedsButDoesNotAccumulate() {
        let acc = TripStatsAccumulator()
            .ingesting(LocationSample(scenarioTime: 0, latitude: 47, longitude: 7, altitudeMeters: 260, speedMps: 10))
        XCTAssertEqual(acc.distanceMeters, 0)
        XCTAssertEqual(acc.rideTimeSeconds, 0)
        // Max speed is computed per-sample so it picks up immediately.
        XCTAssertEqual(acc.maxSpeedKmh, 36.0, accuracy: 0.001)
    }

    func test_twoSamples_distanceAndSpeed() {
        // Two points 0.0001 deg latitude apart at the equator-ish:
        // dy ≈ 0.0001 * 111_000 = 11.1 m. We use 1 second between samples.
        let s1 = LocationSample(scenarioTime: 0, latitude: 47.0, longitude: 7.0, altitudeMeters: 260, speedMps: 0)
        let s2 = LocationSample(scenarioTime: 1, latitude: 47.0001, longitude: 7.0, altitudeMeters: 260, speedMps: 11.1)
        let acc = TripStatsAccumulator().ingesting(s1).ingesting(s2)
        XCTAssertEqual(acc.distanceMeters, 11.1, accuracy: 0.5)
        XCTAssertEqual(acc.rideTimeSeconds, 1)
        XCTAssertEqual(acc.maxSpeedKmh, 11.1 * 3.6, accuracy: 0.01)
        let snap = acc.snapshot
        // average ≈ distance / time * 3.6 ≈ 11.1 * 3.6 ≈ 39.96 km/h → 400
        XCTAssertEqual(snap.averageSpeedKmhX10, 400, accuracy: 4)
    }

    func test_negativeSpeedSamples_skippedForMaxSpeed() {
        let s1 = LocationSample(scenarioTime: 0, latitude: 0, longitude: 0, altitudeMeters: 0, speedMps: 5)
        let s2 = LocationSample(scenarioTime: 1, latitude: 0.0001, longitude: 0, altitudeMeters: 0, speedMps: -1)
        let acc = TripStatsAccumulator().ingesting(s1).ingesting(s2)
        // Max speed is from s1 only (5 m/s = 18 km/h), s2 is skipped.
        XCTAssertEqual(acc.maxSpeedKmh, 18.0, accuracy: 0.01)
        // But distance still accrued from coordinates.
        XCTAssertGreaterThan(acc.distanceMeters, 0)
    }

    func test_altitudeJitterUnderOneMeter_isIgnored() {
        let s1 = LocationSample(scenarioTime: 0, latitude: 0, longitude: 0, altitudeMeters: 100.0, speedMps: 0)
        let s2 = LocationSample(scenarioTime: 1, latitude: 0, longitude: 0, altitudeMeters: 100.5, speedMps: 0) // +0.5 m → ignored
        let s3 = LocationSample(scenarioTime: 2, latitude: 0, longitude: 0, altitudeMeters: 102.0, speedMps: 0) // +1.5 m → counted
        let s4 = LocationSample(scenarioTime: 3, latitude: 0, longitude: 0, altitudeMeters: 99.0, speedMps: 0)  // -3.0 m → counted
        let acc = TripStatsAccumulator()
            .ingesting(s1).ingesting(s2).ingesting(s3).ingesting(s4)
        XCTAssertEqual(acc.ascentMeters, 1.5, accuracy: 0.001)
        XCTAssertEqual(acc.descentMeters, 3.0, accuracy: 0.001)
    }

    func test_negativeTimeDelta_isClampedToZero() {
        let s1 = LocationSample(scenarioTime: 10, latitude: 0, longitude: 0, altitudeMeters: 0, speedMps: 0)
        let s2 = LocationSample(scenarioTime: 5, latitude: 0, longitude: 0, altitudeMeters: 0, speedMps: 0)
        let acc = TripStatsAccumulator().ingesting(s1).ingesting(s2)
        XCTAssertEqual(acc.rideTimeSeconds, 0)
    }

    func test_reset_zerosTotals() {
        let s1 = LocationSample(scenarioTime: 0, latitude: 0, longitude: 0, altitudeMeters: 0, speedMps: 5)
        let s2 = LocationSample(scenarioTime: 5, latitude: 0.001, longitude: 0, altitudeMeters: 0, speedMps: 5)
        let acc = TripStatsAccumulator().ingesting(s1).ingesting(s2)
        XCTAssertGreaterThan(acc.rideTimeSeconds, 0)
        let cleared = acc.reset()
        XCTAssertEqual(cleared.rideTimeSeconds, 0)
        XCTAssertEqual(cleared.distanceMeters, 0)
        XCTAssertEqual(cleared.maxSpeedKmh, 0)
    }

    func test_baselCityLoopReplay_yieldsSensibleTotals() throws {
        let url = Self.scenarioURL
        let scenario = try ScenarioLoader.load(from: url)
        XCTAssertFalse(scenario.locationSamples.isEmpty)

        var acc = TripStatsAccumulator()
        for sample in scenario.locationSamples {
            acc = acc.ingesting(sample)
        }

        let snap = acc.snapshot
        // The basel scenario covers a city loop over ~170 s. Sanity
        // bounds: distance non-zero, ride time within the scenario
        // duration window, max speed > 0 (the scenario carries ground
        // speed metadata), average speed sane.
        XCTAssertGreaterThan(snap.distanceMeters, 0)
        XCTAssertLessThan(snap.distanceMeters, 50_000) // < 50 km, sanity
        XCTAssertGreaterThan(snap.rideTimeSeconds, 0)
        XCTAssertLessThanOrEqual(Double(snap.rideTimeSeconds), scenario.durationSeconds + 1.0)
        XCTAssertLessThanOrEqual(snap.averageSpeedKmhX10, 3000)
        XCTAssertLessThanOrEqual(snap.maxSpeedKmhX10, 3000)
    }

    // MARK: - fixtures

    private static let scenarioRelativePath =
        "../../../../Fixtures/scenarios/basel-city-loop.json"

    static let scenarioURL: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(scenarioRelativePath, isDirectory: false)
            .standardizedFileURL
    }()
}
