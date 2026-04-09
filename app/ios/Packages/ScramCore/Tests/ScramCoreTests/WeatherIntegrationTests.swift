import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

/// End-to-end: replay the Basel scenario file through ScenarioPlayer and
/// assert the WeatherService emits a payload that decodes to the scenario's
/// first weatherSnapshots entry.
final class WeatherIntegrationTests: XCTestCase {
    private static let scenarioRelativePath =
        "../../../../Fixtures/scenarios/basel-city-loop.json"

    private static let scenarioURL: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(scenarioRelativePath, isDirectory: false)
            .standardizedFileURL
    }()

    func test_replayBaselCityLoop_emitsExpectedWeatherPayload() async throws {
        let scenario = try ScenarioLoader.load(from: Self.scenarioURL)
        XCTAssertFalse(
            scenario.weatherSnapshots.isEmpty,
            "scenario has no weather snapshots"
        )
        let expected = scenario.weatherSnapshots[0]

        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)
        let service = WeatherService(provider: env.weather)

        service.start()

        let receivedStream = service.encodedPayloads
        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in receivedStream {
                out.append(blob)
                if out.count == scenario.weatherSnapshots.count {
                    return out
                }
            }
            return out
        }

        let playerTask = Task {
            await player.play(scenario)
        }
        await clock.advance(to: scenario.durationSeconds + 1.0)
        await playerTask.value

        try await Task.sleep(nanoseconds: 50_000_000)
        await env.weather.stop()
        service.stop()

        let received = await collectorTask.value
        XCTAssertEqual(received.count, scenario.weatherSnapshots.count)

        let first = try ScreenPayloadCodec.decode(received[0])
        guard case .weather(let data, let flags) = first else {
            XCTFail("expected weather payload, got \(first)")
            return
        }
        XCTAssertEqual(flags, [])
        XCTAssertEqual(
            data.condition,
            WeatherService.wireCondition(for: expected.condition)
        )
        XCTAssertEqual(
            data.temperatureCelsiusX10,
            WeatherService.clampTemperatureX10(expected.temperatureCelsius)
        )
        XCTAssertEqual(
            data.highCelsiusX10,
            WeatherService.clampTemperatureX10(expected.highCelsius)
        )
        XCTAssertEqual(
            data.lowCelsiusX10,
            WeatherService.clampTemperatureX10(expected.lowCelsius)
        )
        XCTAssertEqual(
            data.locationName,
            WeatherService.truncateLocationName(expected.locationName)
        )
    }
}
