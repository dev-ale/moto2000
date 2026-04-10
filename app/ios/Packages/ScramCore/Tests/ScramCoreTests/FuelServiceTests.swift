import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class FuelServiceTests: XCTestCase {

    func test_emitsPayloadsWithCorrectPercentAndRange() async throws {
        let store = InMemoryFuelLogStore()
        let log = FuelLog(store: store)

        // Seed the log with a full fill: 10000 mL over 250 km = 40 mL/km
        try await log.addFill(FuelFillEntry(
            amountMilliliters: 10_000,
            distanceSinceLastFillKm: 250,
            isFull: true
        ))

        let mock = MockLocationProvider()
        let service = FuelService(
            provider: mock,
            fuelLog: log,
            settings: FuelSettings(tankCapacityMl: 13_000)
        )
        service.start()

        var iterator = service.payloads.makeAsyncIterator()

        // First sample: establishes position, distance = 0
        mock.emit(LocationSample(
            scenarioTime: 0,
            latitude: 47.5596,
            longitude: 7.5886,
            altitudeMeters: 260,
            speedMps: 0
        ))
        let first = await iterator.next()
        XCTAssertNotNil(first)

        // Decode and verify: at distance 0, tank should be full
        if let first, case .fuelEstimate(let fuel, _) = try ScreenPayloadCodec.decode(first) {
            XCTAssertEqual(fuel.tankPercent, 100)
            // Range at 0 distance = 13000 / 40 = 325 km
            XCTAssertEqual(fuel.estimatedRangeKm, 325)
            XCTAssertEqual(fuel.consumptionMlPerKm, 40)
            XCTAssertEqual(fuel.fuelRemainingMl, 13_000)
        } else {
            XCTFail("expected fuelEstimate payload")
        }

        service.stop()
    }

    func test_noFills_emitsUnknownValues() async throws {
        let store = InMemoryFuelLogStore()
        let log = FuelLog(store: store)
        // No fills added

        let mock = MockLocationProvider()
        let service = FuelService(
            provider: mock,
            fuelLog: log,
            settings: FuelSettings()
        )
        service.start()

        var iterator = service.payloads.makeAsyncIterator()

        mock.emit(LocationSample(
            scenarioTime: 0,
            latitude: 47.0,
            longitude: 7.0,
            altitudeMeters: 260,
            speedMps: 0
        ))
        let payload = await iterator.next()
        XCTAssertNotNil(payload)

        if let payload, case .fuelEstimate(let fuel, _) = try ScreenPayloadCodec.decode(payload) {
            XCTAssertEqual(fuel.estimatedRangeKm, FuelData.unknown)
            XCTAssertEqual(fuel.consumptionMlPerKm, FuelData.unknown)
            XCTAssertEqual(fuel.fuelRemainingMl, FuelData.unknown)
        } else {
            XCTFail("expected fuelEstimate payload")
        }

        service.stop()
    }

    func test_distanceTracking_affectsTankPercent() async throws {
        let store = InMemoryFuelLogStore()
        let log = FuelLog(store: store)

        // 40 mL/km consumption
        try await log.addFill(FuelFillEntry(
            amountMilliliters: 10_000,
            distanceSinceLastFillKm: 250,
            isFull: true
        ))

        let mock = MockLocationProvider()
        let service = FuelService(
            provider: mock,
            fuelLog: log,
            settings: FuelSettings(tankCapacityMl: 10_000)
        )
        service.start()

        var iterator = service.payloads.makeAsyncIterator()

        // Emit two points ~11 km apart (Basel to Mulhouse is ~30km,
        // let's use a smaller delta)
        mock.emit(LocationSample(
            scenarioTime: 0,
            latitude: 47.5596,
            longitude: 7.5886,
            altitudeMeters: 260
        ))
        _ = await iterator.next() // first payload at distance 0

        // Move to a point roughly 100km north (each degree latitude ≈ 111 km)
        mock.emit(LocationSample(
            scenarioTime: 3600,
            latitude: 48.4596,
            longitude: 7.5886,
            altitudeMeters: 260
        ))
        let second = await iterator.next()
        XCTAssertNotNil(second)

        // After ~100 km at 40 mL/km, consumed ≈ 4000 mL
        // Remaining ≈ 6000, percent ≈ 60%
        if let second, case .fuelEstimate(let fuel, _) = try ScreenPayloadCodec.decode(second) {
            XCTAssertLessThan(fuel.tankPercent, 100)
            XCTAssertGreaterThan(fuel.tankPercent, 0)
        } else {
            XCTFail("expected fuelEstimate payload")
        }

        service.stop()
    }

    func test_resetDistance_resetsTracking() async throws {
        let store = InMemoryFuelLogStore()
        let log = FuelLog(store: store)

        try await log.addFill(FuelFillEntry(
            amountMilliliters: 10_000,
            distanceSinceLastFillKm: 250,
            isFull: true
        ))

        let mock = MockLocationProvider()
        let service = FuelService(
            provider: mock,
            fuelLog: log,
            settings: FuelSettings(tankCapacityMl: 13_000)
        )
        service.start()

        var iterator = service.payloads.makeAsyncIterator()

        mock.emit(LocationSample(scenarioTime: 0, latitude: 47.0, longitude: 7.0))
        _ = await iterator.next()

        mock.emit(LocationSample(scenarioTime: 100, latitude: 47.5, longitude: 7.0))
        _ = await iterator.next()

        // Distance should be non-zero
        XCTAssertGreaterThan(service.currentDistanceKm, 0)

        service.resetDistance()
        XCTAssertEqual(service.currentDistanceKm, 0, accuracy: 0.001)

        service.stop()
    }
}
