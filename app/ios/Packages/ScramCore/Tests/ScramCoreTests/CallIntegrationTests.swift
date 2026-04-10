import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

/// End-to-end test that replays `basel-city-loop.json` through the
/// ScenarioPlayer -> MockCallObserver -> CallAlertService pipeline and
/// asserts every scenario `callEvents` entry arrives on the encoded
/// BLE payload stream with correct ALERT flags.
///
/// The basel-city-loop scenario has call events at 90s (incoming) and
/// 110s (ended).
final class CallIntegrationTests: XCTestCase {
    private static let scenarioRelativePath =
        "../../../../Fixtures/scenarios/basel-city-loop.json"

    private static let scenarioURL: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(scenarioRelativePath, isDirectory: false)
            .standardizedFileURL
    }()

    func test_replayBaselCityLoop_emitsExpectedCallStream() async throws {
        let scenario = try ScenarioLoader.load(from: Self.scenarioURL)
        XCTAssertGreaterThanOrEqual(
            scenario.callEvents.count,
            2,
            "scenario must have at least two call events (incoming + ended)"
        )

        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)
        let service = CallAlertService(observer: env.calls)
        service.start()

        let receivedStream = service.encodedPayloads
        let expectedCount = scenario.callEvents.count
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

        // Let the forwarding task drain buffered events.
        try await Task.sleep(nanoseconds: 50_000_000)
        await env.calls.stop()
        service.stop()

        let received = await collectorTask.value
        XCTAssertEqual(received.count, scenario.callEvents.count)

        // Decode each blob and verify against the scenario event.
        for (blob, expected) in zip(received, scenario.callEvents) {
            let payload = try ScreenPayloadCodec.decode(blob)
            guard case .incomingCall(let call, let flags) = payload else {
                XCTFail("expected incomingCall payload, got \(payload)")
                continue
            }
            // Call state matches
            let expectedState: IncomingCallData.CallStateWire
            switch expected.state {
            case .incoming: expectedState = .incoming
            case .connected: expectedState = .connected
            case .ended: expectedState = .ended
            }
            XCTAssertEqual(call.callState, expectedState)

            // Caller handle matches (possibly truncated)
            XCTAssertTrue(
                expected.callerHandle.hasPrefix(call.callerHandle) ||
                call.callerHandle == CallAlertService.truncateUTF8(
                    expected.callerHandle,
                    maxByteCount: IncomingCallData.callerHandleFieldLength - 1
                )
            )

            // ALERT flag: set for incoming/connected, cleared for ended
            switch expected.state {
            case .incoming, .connected:
                XCTAssertTrue(flags.contains(.alert),
                              "ALERT flag must be set for \(expected.state)")
            case .ended:
                XCTAssertFalse(flags.contains(.alert),
                               "ALERT flag must NOT be set for ended")
            }
        }
    }
}
