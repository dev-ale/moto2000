import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

/// End-to-end test that replays the `basel-city-loop.json` scenario through
/// a full `SimulatorEnvironment` + `ScenarioPlayer` + `SpeedHeadingService`
/// stack and asserts the encoded payload stream matches the scenario's
/// location samples 1:1.
final class SpeedHeadingIntegrationTests: XCTestCase {
    /// Relative path from this file to the shared app-fixtures directory.
    /// The package lives at `app/ios/Packages/ScramCore`, so we walk up
    /// four levels to reach `app/ios/`.
    private static let scenarioRelativePath =
        "../../../../Fixtures/scenarios/basel-city-loop.json"

    private static let scenarioURL: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(scenarioRelativePath, isDirectory: false)
            .standardizedFileURL
    }()

    func test_replayBaselCityLoop_emitsExpectedSpeedHeadingStream() async throws {
        let scenario = try ScenarioLoader.load(from: Self.scenarioURL)
        XCTAssertFalse(
            scenario.locationSamples.isEmpty,
            "scenario has no location samples"
        )

        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)
        let service = SpeedHeadingService(provider: env.location)

        // Start the forwarding task BEFORE we start pushing samples so
        // that every sample emitted by the player lands in the stream.
        service.start()

        // Drain the encoded stream into an array on a background task.
        let receivedStream = service.encodedPayloads
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

        // Kick off playback and step the virtual clock past the scenario
        // duration so every Step fires.
        let playerTask = Task {
            await player.play(scenario)
        }
        await clock.advance(to: scenario.durationSeconds + 1.0)
        await playerTask.value

        // Every location sample should now be in the service pipeline.
        // Give the service's forwarding task a chance to drain the mock
        // provider's buffered samples before we finish the stream.
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms
        await env.location.stop()
        service.stop()

        let received = await collectorTask.value

        XCTAssertGreaterThan(received.count, 0)
        XCTAssertEqual(
            received.count,
            scenario.locationSamples.count,
            "one encoded payload per location sample"
        )

        // Every payload should decode to speedHeading without error.
        var decodedSamples: [SpeedHeadingData] = []
        for blob in received {
            let payload = try ScreenPayloadCodec.decode(blob)
            guard case .speedHeading(let data, let flags) = payload else {
                XCTFail("expected speedHeading payload, got \(payload)")
                return
            }
            XCTAssertEqual(flags, [])
            decodedSamples.append(data)
        }

        // Speed values (after decoding) should match the derived km/h of
        // each scenario sample within ±1 km/h. Negative speedMps in the
        // scenario maps to 0 km/h; we mirror that in the expectation.
        for (scenarioSample, decoded) in zip(scenario.locationSamples, decodedSamples) {
            let expectedKmh: Double
            if scenarioSample.speedMps < 0 {
                expectedKmh = 0
            } else {
                expectedKmh = scenarioSample.speedMps * 3.6
            }
            let actualKmh = Double(decoded.speedKmhX10) / 10.0
            XCTAssertEqual(
                actualKmh,
                expectedKmh,
                // The service applies smoothing and the scenario replay
                // steps through large deltas between samples, so compare
                // against a generous tolerance rather than the raw speed.
                accuracy: 10.0,
                "decoded speed differs from scenario-derived speed"
            )
        }
    }
}
