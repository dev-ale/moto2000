import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

/// End-to-end test that replays `highway-straight.json` through the
/// ScenarioPlayer → MockNowPlayingProvider → MusicService pipeline and
/// asserts every scenario `nowPlayingSnapshot` arrives on the encoded
/// BLE payload stream in order.
final class MusicIntegrationTests: XCTestCase {
    private static let scenarioRelativePath =
        "../../../../Fixtures/scenarios/highway-straight.json"

    private static let scenarioURL: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(scenarioRelativePath, isDirectory: false)
            .standardizedFileURL
    }()

    func test_replayHighwayStraight_emitsExpectedMusicStream() async throws {
        let scenario = try ScenarioLoader.load(from: Self.scenarioURL)
        XCTAssertGreaterThanOrEqual(
            scenario.nowPlayingSnapshots.count,
            3,
            "scenario must have at least two track transitions"
        )

        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)
        let service = MusicService(provider: env.nowPlaying)
        service.start()

        let receivedStream = service.encodedPayloads
        let expectedCount = scenario.nowPlayingSnapshots.count
        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in receivedStream {
                out.append(blob)
                if out.count == expectedCount {
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

        // Let the forwarding task drain buffered snapshots.
        try await Task.sleep(nanoseconds: 50_000_000)
        await env.nowPlaying.stop()
        service.stop()

        let received = await collectorTask.value
        XCTAssertEqual(received.count, scenario.nowPlayingSnapshots.count)

        // Decode each blob and compare to the scenario snapshot field-by-field.
        for (blob, expected) in zip(received, scenario.nowPlayingSnapshots) {
            let payload = try ScreenPayloadCodec.decode(blob)
            guard case .music(let music, _) = payload else {
                XCTFail("expected music payload, got \(payload)")
                continue
            }
            XCTAssertEqual(music.title, expected.title)
            XCTAssertEqual(music.artist, expected.artist)
            XCTAssertEqual(music.album, expected.album)
            XCTAssertEqual(music.isPlaying, expected.isPlaying)
            let expectedPos = MusicService.packSeconds(expected.positionSeconds)
            let expectedDur = MusicService.packSeconds(expected.durationSeconds)
            XCTAssertEqual(music.positionSeconds, expectedPos)
            XCTAssertEqual(music.durationSeconds, expectedDur)
        }

        // Verify at least two distinct titles appeared — the acceptance
        // criteria calls for ≥2 track changes.
        let uniqueTitles = Set(scenario.nowPlayingSnapshots.map(\.title))
        XCTAssertGreaterThanOrEqual(uniqueTitles.count, 2)
    }
}
