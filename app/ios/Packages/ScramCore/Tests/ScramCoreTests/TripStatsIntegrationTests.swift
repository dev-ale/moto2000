import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

/// End-to-end test that replays the `basel-city-loop.json` scenario through
/// a full `SimulatorEnvironment` + `ScenarioPlayer` + `TripStatsService`
/// stack and asserts the final encoded payload reports sensible totals.
final class TripStatsIntegrationTests: XCTestCase {
    private static let scenarioRelativePath =
        "../../../../Fixtures/scenarios/basel-city-loop.json"

    private static let scenarioURL: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(scenarioRelativePath, isDirectory: false)
            .standardizedFileURL
    }()

    func test_replayBaselCityLoop_emitsExpectedTripStatsTotals() async throws {
        let scenario = try ScenarioLoader.load(from: Self.scenarioURL)
        XCTAssertFalse(scenario.locationSamples.isEmpty)

        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)
        let service = TripStatsService(provider: env.location)

        service.start()

        let receivedStream = service.payloads
        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in receivedStream {
                out.append(blob)
                if out.count == scenario.locationSamples.count {
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
            scenario.locationSamples.count,
            "expected one trip-stats payload per location sample"
        )

        guard let last = received.last else {
            XCTFail("no payloads received")
            return
        }
        let payload = try ScreenPayloadCodec.decode(last)
        guard case .tripStats(let stats, let flags) = payload else {
            XCTFail("expected tripStats payload, got \(payload)")
            return
        }
        XCTAssertEqual(flags, [])
        XCTAssertGreaterThan(stats.distanceMeters, 0)
        XCTAssertGreaterThan(stats.rideTimeSeconds, 0)
        XCTAssertLessThanOrEqual(Double(stats.rideTimeSeconds), scenario.durationSeconds + 1.0)
        XCTAssertGreaterThan(stats.maxSpeedKmhX10, 0)
    }
}
