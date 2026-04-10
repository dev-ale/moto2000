import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

/// End-to-end test that replays the `basel-city-loop.json` scenario through
/// a full `SimulatorEnvironment` + `ScenarioPlayer` + `FuelService` stack
/// with a pre-seeded fill log, and asserts the final payload has sensible
/// fuel estimates.
final class FuelIntegrationTests: XCTestCase {
    private static let scenarioRelativePath =
        "../../../../Fixtures/scenarios/basel-city-loop.json"

    private static let scenarioURL: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(scenarioRelativePath, isDirectory: false)
            .standardizedFileURL
    }()

    func test_replayBaselCityLoop_emitsSensibleFuelEstimates() async throws {
        let scenario = try ScenarioLoader.load(from: Self.scenarioURL)
        XCTAssertFalse(scenario.locationSamples.isEmpty)

        // Pre-seed with a realistic fill: 40 mL/km consumption
        let store = InMemoryFuelLogStore(entries: [
            FuelFillEntry(
                date: Date(timeIntervalSince1970: 0),
                amountMilliliters: 10_000,
                distanceSinceLastFillKm: 250,
                isFull: true
            ),
        ])
        let log = FuelLog(store: store)
        let settings = FuelSettings(tankCapacityMl: 13_000)

        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)
        let service = FuelService(
            provider: env.location,
            fuelLog: log,
            settings: settings
        )

        service.start()

        let receivedStream = service.payloads
        let sampleCount = scenario.locationSamples.count
        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in receivedStream {
                out.append(blob)
                if out.count == sampleCount {
                    return out
                }
            }
            return out
        }

        let playerTask = Task { await player.play(scenario) }
        await clock.advance(to: scenario.durationSeconds + 1.0)
        await playerTask.value

        try await Task.sleep(nanoseconds: 50_000_000)
        await env.location.stop()
        service.stop()

        let received = await collectorTask.value
        XCTAssertEqual(
            received.count,
            sampleCount,
            "expected one fuel payload per location sample"
        )

        guard let last = received.last else {
            XCTFail("no payloads received")
            return
        }
        let payload = try ScreenPayloadCodec.decode(last)
        guard case .fuelEstimate(let fuel, let flags) = payload else {
            XCTFail("expected fuelEstimate payload, got \(payload)")
            return
        }
        XCTAssertEqual(flags, [])

        // After driving the Basel city loop (~5-10 km), fuel should have
        // decreased but not by much on a 13L tank
        XCTAssertLessThanOrEqual(fuel.tankPercent, 100)
        XCTAssertGreaterThan(fuel.tankPercent, 50, "tank should still be mostly full after a city loop")

        // Range should be known (not 0xFFFF)
        XCTAssertNotEqual(fuel.estimatedRangeKm, FuelData.unknown)
        XCTAssertGreaterThan(fuel.estimatedRangeKm, 0)

        // Consumption should be 40 mL/km
        XCTAssertEqual(fuel.consumptionMlPerKm, 40)

        // Remaining should be less than full tank
        XCTAssertNotEqual(fuel.fuelRemainingMl, FuelData.unknown)
        XCTAssertLessThan(fuel.fuelRemainingMl, 13_000)
        XCTAssertGreaterThan(fuel.fuelRemainingMl, 0)
    }
}
