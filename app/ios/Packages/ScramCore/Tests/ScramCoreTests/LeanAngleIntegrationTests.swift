import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

/// End-to-end test that replays the `twisty-mountain.json` motion-only
/// scenario through ScenarioPlayer + LeanAngleService and asserts that
/// the encoded payload stream peaks at sensible left/right lean values.
final class LeanAngleIntegrationTests: XCTestCase {
    private static let scenarioRelativePath =
        "../../../../Fixtures/scenarios/twisty-mountain.json"

    private static let scenarioURL: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(scenarioRelativePath, isDirectory: false)
            .standardizedFileURL
    }()

    func test_replayTwistyMountain_peaksAtExpectedLeanAngles() async throws {
        let scenario = try ScenarioLoader.load(from: Self.scenarioURL)
        XCTAssertFalse(
            scenario.motionSamples.isEmpty,
            "scenario must carry motion samples"
        )

        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)
        let service = LeanAngleService(provider: env.motion)

        service.start()

        let receivedStream = service.encodedPayloads
        let expected = scenario.motionSamples.count
        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in receivedStream {
                out.append(blob)
                if out.count == expected {
                    return out
                }
            }
            return out
        }

        let playerTask = Task { await player.play(scenario) }
        await clock.advance(to: scenario.durationSeconds + 1.0)
        await playerTask.value
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms drain
        await env.motion.stop()
        service.stop()

        let received = await collectorTask.value
        XCTAssertEqual(received.count, scenario.motionSamples.count)

        var peakLeft: UInt16 = 0
        var peakRight: UInt16 = 0
        var lastDecoded: LeanAngleData?
        for blob in received {
            let payload = try ScreenPayloadCodec.decode(blob)
            guard case .leanAngle(let data, _) = payload else {
                XCTFail("expected leanAngle payload")
                return
            }
            if data.maxLeftLeanDegX10 > peakLeft { peakLeft = data.maxLeftLeanDegX10 }
            if data.maxRightLeanDegX10 > peakRight { peakRight = data.maxRightLeanDegX10 }
            lastDecoded = data
        }

        let final = try XCTUnwrap(lastDecoded)
        // The CSV holds ~40° on each side for several samples and then
        // returns to upright. With α=0.2 the EMA gets close to but not
        // exactly at the steady-state value, so we assert reasonable
        // peaks rather than exact equalities.
        XCTAssertGreaterThan(peakRight, 200, "max right lean should clear 20°")
        XCTAssertGreaterThan(peakLeft, 200, "max left lean should clear 20°")
        XCTAssertLessThanOrEqual(peakRight, 500, "max right lean should not blow past the synthetic peak")
        XCTAssertLessThanOrEqual(peakLeft, 500, "max left lean should not blow past the synthetic peak")
        // The scenario ends with several samples upright, so the final
        // current lean should be near zero.
        XCTAssertLessThan(abs(Int(final.currentLeanDegX10)), 100, "current should be within ±10° at the end")
    }
}
