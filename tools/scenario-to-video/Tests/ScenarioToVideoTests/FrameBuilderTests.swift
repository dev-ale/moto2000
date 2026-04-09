import XCTest
import BLEProtocol
import RideSimulatorKit
@testable import ScenarioToVideo

final class FrameBuilderTests: XCTestCase {
    // MARK: - Empty scenario

    func testEmptyScenarioProducesOneFrame() throws {
        let scenario = Scenario(
            name: "empty", summary: "", durationSeconds: 0
        )
        let builder = FrameBuilder(scenario: scenario, screen: .speedHeading)
        XCTAssertEqual(builder.frameCount, 1)
        let frames = try builder.allFrames()
        XCTAssertEqual(frames.count, 1)
        guard case .speedHeading(let data, _) = frames[0].payload else {
            return XCTFail("expected speedHeading payload")
        }
        XCTAssertEqual(data.speedKmhX10, 0)
        XCTAssertEqual(data.headingDegX10, 0)
    }

    func testScenarioDurationControlsFrameCount() {
        let scenario = Scenario(
            name: "sixty", summary: "", durationSeconds: 60
        )
        // 0..60 at stepSeconds 1 → 61 frames (both endpoints rendered).
        let builder = FrameBuilder(scenario: scenario, screen: .speedHeading)
        XCTAssertEqual(builder.frameCount, 61)
    }

    // MARK: - Speed derivation

    func testSpeedFromLocationSample() throws {
        let loc = LocationSample(
            scenarioTime: 0,
            latitude: 47.56,
            longitude: 7.58,
            altitudeMeters: 260,
            speedMps: 10,            // 36 km/h → 360
            courseDegrees: 45,
            horizontalAccuracyMeters: 5
        )
        let scenario = Scenario(
            name: "s", summary: "", durationSeconds: 2,
            locationSamples: [loc]
        )
        let builder = FrameBuilder(scenario: scenario, screen: .speedHeading)
        let frame = try builder.frame(at: 0)
        guard case .speedHeading(let data, _) = frame.payload else {
            return XCTFail()
        }
        XCTAssertEqual(data.speedKmhX10, 360)
        XCTAssertEqual(data.headingDegX10, 450)
        XCTAssertEqual(data.altitudeMeters, 260)
        XCTAssertEqual(data.temperatureCelsiusX10, 0)
    }

    func testSpeedClampedToMax() throws {
        let loc = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            speedMps: 1000, courseDegrees: 0
        )
        let scenario = Scenario(
            name: "s", summary: "", durationSeconds: 1,
            locationSamples: [loc]
        )
        let builder = FrameBuilder(scenario: scenario, screen: .speedHeading)
        let frame = try builder.frame(at: 0)
        guard case .speedHeading(let data, _) = frame.payload else {
            return XCTFail()
        }
        XCTAssertEqual(data.speedKmhX10, 3000)
    }

    func testNegativeSpeedBecomesZero() throws {
        let loc = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            speedMps: -1, courseDegrees: -1
        )
        let scenario = Scenario(
            name: "s", summary: "", durationSeconds: 1,
            locationSamples: [loc]
        )
        let builder = FrameBuilder(scenario: scenario, screen: .speedHeading)
        let frame = try builder.frame(at: 0)
        guard case .speedHeading(let data, _) = frame.payload else {
            return XCTFail()
        }
        XCTAssertEqual(data.speedKmhX10, 0)
        XCTAssertEqual(data.headingDegX10, 0)
    }

    // MARK: - Heading derivation

    func testHeadingPrefersHeadingSampleOverCourse() throws {
        let loc = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            speedMps: 5, courseDegrees: 10
        )
        let heading = HeadingSample(scenarioTime: 0, magneticDegrees: 200)
        let scenario = Scenario(
            name: "s", summary: "", durationSeconds: 1,
            locationSamples: [loc],
            headingSamples: [heading]
        )
        let builder = FrameBuilder(scenario: scenario, screen: .speedHeading)
        let frame = try builder.frame(at: 0)
        guard case .speedHeading(let data, _) = frame.payload else {
            return XCTFail()
        }
        XCTAssertEqual(data.headingDegX10, 2000)
    }

    func testHeadingNormalisedWhenOutOfRange() throws {
        let heading = HeadingSample(scenarioTime: 0, magneticDegrees: 725)
        // 725 mod 360 = 5.
        let scenario = Scenario(
            name: "s", summary: "", durationSeconds: 1,
            headingSamples: [heading]
        )
        let builder = FrameBuilder(scenario: scenario, screen: .speedHeading)
        let frame = try builder.frame(at: 0)
        guard case .speedHeading(let data, _) = frame.payload else {
            return XCTFail()
        }
        XCTAssertEqual(data.headingDegX10, 50)
    }

    // MARK: - Sample gaps

    func testSampleAtOrBeforeUsesLatestPriorSample() throws {
        let locs = [
            LocationSample(scenarioTime: 0, latitude: 0, longitude: 0, speedMps: 5, courseDegrees: 0),
            LocationSample(scenarioTime: 10, latitude: 0, longitude: 0, speedMps: 20, courseDegrees: 0),
            LocationSample(scenarioTime: 30, latitude: 0, longitude: 0, speedMps: 0, courseDegrees: 0),
        ]
        let scenario = Scenario(
            name: "s", summary: "", durationSeconds: 40,
            locationSamples: locs
        )
        let builder = FrameBuilder(scenario: scenario, screen: .speedHeading)
        // At t=5 we should still see the first sample (5 m/s → 180).
        guard case .speedHeading(let d0, _) = try builder.frame(at: 5).payload else {
            return XCTFail()
        }
        XCTAssertEqual(d0.speedKmhX10, 180)
        // At t=15 the second sample (20 m/s → 720).
        guard case .speedHeading(let d1, _) = try builder.frame(at: 15).payload else {
            return XCTFail()
        }
        XCTAssertEqual(d1.speedKmhX10, 720)
        // At t=35 the third sample (0 m/s → 0).
        guard case .speedHeading(let d2, _) = try builder.frame(at: 35).payload else {
            return XCTFail()
        }
        XCTAssertEqual(d2.speedKmhX10, 0)
    }

    func testTimeBeyondLastSampleHolds() throws {
        let loc = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            speedMps: 10, courseDegrees: 90
        )
        let scenario = Scenario(
            name: "s", summary: "", durationSeconds: 5,
            locationSamples: [loc]
        )
        let builder = FrameBuilder(scenario: scenario, screen: .speedHeading)
        let last = try builder.frame(at: builder.frameCount - 1)
        guard case .speedHeading(let data, _) = last.payload else {
            return XCTFail()
        }
        XCTAssertEqual(data.speedKmhX10, 360)
        XCTAssertEqual(data.headingDegX10, 900)
    }

    // MARK: - Clock derivation

    func testClockIsDeterministic() throws {
        let scenario = Scenario(
            name: "s", summary: "", durationSeconds: 3
        )
        let builder = FrameBuilder(scenario: scenario, screen: .clock)
        let f0 = try builder.frame(at: 0)
        let f2 = try builder.frame(at: 2)
        guard case .clock(let c0, _) = f0.payload,
              case .clock(let c2, _) = f2.payload
        else {
            return XCTFail("expected clock payloads")
        }
        XCTAssertEqual(c0.unixTime, FrameBuilder.clockEpochSeconds)
        XCTAssertEqual(c2.unixTime, FrameBuilder.clockEpochSeconds + 2)
        XCTAssertEqual(c0.tzOffsetMinutes, 0)
        XCTAssertTrue(c0.is24Hour)
    }

    // MARK: - Rotating screen

    func testRotatingAlternatesScreens() throws {
        let scenario = Scenario(
            name: "s", summary: "", durationSeconds: 25
        )
        let builder = FrameBuilder(
            scenario: scenario, screen: .rotating(holdSeconds: 10)
        )
        let frames = try builder.allFrames()
        // First 10 frames → clock, next 10 → speedHeading, last → clock.
        if case .clock = frames[0].payload {} else { XCTFail() }
        if case .clock = frames[9].payload {} else { XCTFail() }
        if case .speedHeading = frames[10].payload {} else { XCTFail() }
        if case .speedHeading = frames[19].payload {} else { XCTFail() }
        if case .clock = frames[20].payload {} else { XCTFail() }
    }

    // MARK: - Encoding round-trip

    func testPayloadsAreEncodable() throws {
        let scenario = Scenario(
            name: "s", summary: "", durationSeconds: 3,
            locationSamples: [
                LocationSample(
                    scenarioTime: 0, latitude: 0, longitude: 0,
                    altitudeMeters: 100, speedMps: 5, courseDegrees: 90
                )
            ]
        )
        let builder = FrameBuilder(scenario: scenario, screen: .speedHeading)
        for i in 0..<builder.frameCount {
            let frame = try builder.frame(at: i)
            let bytes = try ScreenPayloadCodec.encode(frame.payload)
            XCTAssertFalse(bytes.isEmpty)
            // Round-trip decode must succeed.
            _ = try ScreenPayloadCodec.decode(bytes)
        }
    }
}
