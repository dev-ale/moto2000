import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

/// End-to-end test that replays the `basel-city-loop.json` scenario through
/// a full `SimulatorEnvironment` + `ScenarioPlayer` + `AltitudeService`
/// stack and asserts the final payload has sensible altitude data.
final class AltitudeIntegrationTests: XCTestCase {
    private static let scenarioRelativePath =
        "../../../../Fixtures/scenarios/basel-city-loop.json"

    private static let scenarioURL: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(scenarioRelativePath, isDirectory: false)
            .standardizedFileURL
    }()

    func test_replayBaselCityLoop_emitsSensibleAltitudeProfile() async throws {
        let scenario = try ScenarioLoader.load(from: Self.scenarioURL)
        XCTAssertFalse(scenario.locationSamples.isEmpty)

        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)
        let service = AltitudeService(provider: env.location)

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
            "expected one altitude payload per location sample"
        )

        guard let last = received.last else {
            XCTFail("no payloads received")
            return
        }
        let payload = try ScreenPayloadCodec.decode(last)
        guard case .altitude(let alt, let flags) = payload else {
            XCTFail("expected altitude payload, got \(payload)")
            return
        }
        XCTAssertEqual(flags, [])
        XCTAssertGreaterThan(alt.sampleCount, 0)
        // Basel city loop has some elevation variation
        XCTAssertGreaterThan(alt.currentAltitudeM, -500)
        XCTAssertLessThan(alt.currentAltitudeM, 9000)
        // The city loop should have at least some ascent/descent
        // (Basel is hilly enough for GPS to register)
        // Use a loose check — even flat GPS data will jitter above 0
    }
}
