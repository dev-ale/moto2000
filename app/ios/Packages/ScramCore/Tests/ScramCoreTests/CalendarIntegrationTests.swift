import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

/// End-to-end test that replays `basel-city-loop.json` through the
/// ScenarioPlayer -> MockCalendarProvider -> CalendarService pipeline and
/// asserts every scenario `calendarEvents` entry arrives on the encoded
/// BLE payload stream.
final class CalendarIntegrationTests: XCTestCase {
    private static let scenarioRelativePath =
        "../../../../Fixtures/scenarios/basel-city-loop.json"

    private static let scenarioURL: URL = {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()
            .appendingPathComponent(scenarioRelativePath, isDirectory: false)
            .standardizedFileURL
    }()

    func test_replayBaselCityLoop_emitsExpectedCalendarStream() async throws {
        let scenario = try ScenarioLoader.load(from: Self.scenarioURL)
        XCTAssertGreaterThanOrEqual(
            scenario.calendarEvents.count,
            1,
            "scenario must have at least one calendar event"
        )

        let env = SimulatorEnvironment()
        let clock = VirtualClock()
        let player = ScenarioPlayer(environment: env, clock: clock)
        let service = CalendarService(provider: env.calendar)
        service.start()

        let receivedStream = service.encodedPayloads
        let expectedCount = scenario.calendarEvents.count
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
        await env.calendar.stop()
        service.stop()

        let received = await collectorTask.value
        XCTAssertEqual(received.count, scenario.calendarEvents.count)

        // Decode each blob and compare to the scenario event.
        for (blob, expected) in zip(received, scenario.calendarEvents) {
            let payload = try ScreenPayloadCodec.decode(blob)
            guard case .appointment(let data, _) = payload else {
                XCTFail("expected appointment payload, got \(payload)")
                continue
            }
            let expectedMinutes = CalendarService.secondsToMinutesClamped(expected.startsInSeconds)
            XCTAssertEqual(data.startsInMinutes, expectedMinutes)
            // Title should be truncated if needed but match for short titles.
            XCTAssertTrue(expected.title.hasPrefix(data.title) || data.title == CalendarService.truncateUTF8(expected.title, maxByteCount: CalendarService.maxTitleUTF8Bytes))
            XCTAssertTrue(expected.location.hasPrefix(data.location) || data.location == CalendarService.truncateUTF8(expected.location, maxByteCount: CalendarService.maxLocationUTF8Bytes))
        }
    }
}
