import XCTest

@testable import RideSimulatorKit

final class ScenarioRecorderTests: XCTestCase {
    func test_recorderCapturesEventsWithClockTimestamps() async {
        let clock = VirtualClock()
        let recorder = ScenarioRecorder(clock: clock, name: "captured")

        await recorder.start()
        await clock.advance(to: 1)
        await recorder.record(LocationSample(scenarioTime: 0, latitude: 0, longitude: 0))
        await clock.advance(to: 2)
        await recorder.record(HeadingSample(scenarioTime: 0, magneticDegrees: 45))
        await clock.advance(to: 3)
        await recorder.record(CallEvent(scenarioTime: 0, state: .incoming, callerHandle: "contact-1"))
        await clock.advance(to: 10)
        let scenario = await recorder.stop()

        XCTAssertEqual(scenario.name, "captured")
        XCTAssertEqual(scenario.durationSeconds, 10)
        XCTAssertEqual(scenario.locationSamples.count, 1)
        XCTAssertEqual(scenario.locationSamples[0].scenarioTime, 1)
        XCTAssertEqual(scenario.headingSamples[0].scenarioTime, 2)
        XCTAssertEqual(scenario.callEvents[0].scenarioTime, 3)
    }

    func test_recorderIgnoresEventsBeforeStart() async {
        let clock = VirtualClock()
        let recorder = ScenarioRecorder(clock: clock, name: "pre")
        await recorder.record(LocationSample(scenarioTime: 0, latitude: 0, longitude: 0))
        await recorder.start()
        let scenario = await recorder.stop()
        XCTAssertTrue(scenario.locationSamples.isEmpty)
    }

    func test_recordedScenarioRoundTripsThroughJSON() async throws {
        let clock = VirtualClock()
        let recorder = ScenarioRecorder(clock: clock, name: "roundtrip", summary: "captured and replayed")
        await recorder.start()
        await clock.advance(to: 1)
        await recorder.record(LocationSample(scenarioTime: 0, latitude: 47.5, longitude: 7.6))
        await clock.advance(to: 2)
        let scenario = await recorder.stop()

        let bytes = try ScenarioLoader.encode(scenario)
        let decoded = try ScenarioLoader.decode(bytes)
        XCTAssertEqual(decoded, scenario)
    }
}
