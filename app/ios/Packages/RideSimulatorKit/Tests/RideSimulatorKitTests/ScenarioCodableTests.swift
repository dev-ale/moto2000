import XCTest

@testable import RideSimulatorKit

final class ScenarioCodableTests: XCTestCase {
    private func sample() -> Scenario {
        Scenario(
            name: "roundtrip-sample",
            summary: "A little bit of everything",
            durationSeconds: 60,
            locationSamples: [
                LocationSample(scenarioTime: 0, latitude: 47.5, longitude: 7.6),
                LocationSample(scenarioTime: 1, latitude: 47.501, longitude: 7.601, speedMps: 12),
            ],
            headingSamples: [
                HeadingSample(scenarioTime: 0, magneticDegrees: 180),
            ],
            motionSamples: [
                MotionSample(scenarioTime: 0, gravityX: 0, gravityY: -1, gravityZ: 0),
            ],
            weatherSnapshots: [
                WeatherSnapshot(
                    scenarioTime: 0,
                    condition: .clear,
                    temperatureCelsius: 18,
                    highCelsius: 22,
                    lowCelsius: 11,
                    locationName: "Basel"
                ),
            ],
            nowPlayingSnapshots: [
                NowPlayingSnapshot(
                    scenarioTime: 5,
                    title: "Track",
                    artist: "Artist",
                    album: "Album",
                    isPlaying: true,
                    positionSeconds: 0,
                    durationSeconds: 200
                ),
            ],
            callEvents: [
                CallEvent(scenarioTime: 30, state: .incoming, callerHandle: "contact-1"),
            ],
            calendarEvents: [
                CalendarEvent(scenarioTime: 0, title: "Coffee", startsInSeconds: 1800, location: "Kaffee"),
            ]
        )
    }

    func test_encodeDecode_roundTrip() throws {
        let original = sample()
        let bytes = try ScenarioLoader.encode(original)
        let decoded = try ScenarioLoader.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_decode_rejectsUnsupportedVersion() throws {
        var scenario = sample()
        scenario.version = 999
        let bytes = try ScenarioLoader.encode(scenario)
        XCTAssertThrowsError(try ScenarioLoader.decode(bytes)) { error in
            XCTAssertEqual(error as? ScenarioError, .unsupportedVersion(999))
        }
    }

    func test_emptyScenarioIsValid() throws {
        let empty = Scenario(name: "empty", summary: "", durationSeconds: 0)
        let bytes = try ScenarioLoader.encode(empty)
        let decoded = try ScenarioLoader.decode(bytes)
        XCTAssertEqual(decoded, empty)
    }
}
