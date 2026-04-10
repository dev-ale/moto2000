import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class CompassServiceTests: XCTestCase {
    func test_encode_validCourseProducesCorrectCompassData() {
        let service = CompassService(provider: StubProvider())
        let sample = LocationSample(
            scenarioTime: 0,
            latitude: 0,
            longitude: 0,
            altitudeMeters: 0,
            speedMps: 10, // well above 3 km/h threshold
            courseDegrees: 135.5,
            horizontalAccuracyMeters: 10
        )
        let blob = service.encode(sample)
        XCTAssertNotNil(blob)
        let payload = try? ScreenPayloadCodec.decode(blob!)
        guard case .compass(let data, _) = payload else {
            XCTFail("expected compass payload")
            return
        }
        XCTAssertEqual(data.magneticHeadingDegX10, 1355)
        XCTAssertEqual(data.trueHeadingDegX10, 1355)
        XCTAssertEqual(data.headingAccuracyDegX10, 100) // 10m -> 10.0 deg -> 100
        XCTAssertTrue(data.useTrueHeading)
    }

    func test_encode_invalidCourseHoldsLastKnownHeading() {
        let service = CompassService(provider: StubProvider())

        // First sample: establish a known heading.
        let first = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            altitudeMeters: 0, speedMps: 10, courseDegrees: 270.0
        )
        _ = service.encode(first)

        // Second sample: course = -1 (invalid).
        let second = LocationSample(
            scenarioTime: 1, latitude: 0, longitude: 0,
            altitudeMeters: 0, speedMps: 10, courseDegrees: -1
        )
        let blob = service.encode(second)
        XCTAssertNotNil(blob)
        let payload = try? ScreenPayloadCodec.decode(blob!)
        guard case .compass(let data, _) = payload else {
            XCTFail("expected compass payload")
            return
        }
        // Should retain the previous heading of 270 degrees.
        XCTAssertEqual(data.magneticHeadingDegX10, 2700)
        XCTAssertEqual(data.trueHeadingDegX10, 2700)
    }

    func test_encode_standstillHoldsLastKnownHeading() {
        let service = CompassService(provider: StubProvider())

        // First sample: moving, heading established.
        let moving = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            altitudeMeters: 0, speedMps: 10, courseDegrees: 45.0
        )
        _ = service.encode(moving)

        // Second sample: speed below 3 km/h (0.5 m/s ~ 1.8 km/h).
        let slow = LocationSample(
            scenarioTime: 1, latitude: 0, longitude: 0,
            altitudeMeters: 0, speedMps: 0.5, courseDegrees: 180.0
        )
        let blob = service.encode(slow)
        XCTAssertNotNil(blob)
        let payload = try? ScreenPayloadCodec.decode(blob!)
        guard case .compass(let data, _) = payload else {
            XCTFail("expected compass payload")
            return
        }
        // Should retain the previous heading of 45 degrees, not 180.
        XCTAssertEqual(data.magneticHeadingDegX10, 450)
        XCTAssertEqual(data.trueHeadingDegX10, 450)
    }

    func test_encode_headingWrapsWith360() {
        let service = CompassService(provider: StubProvider())
        let sample = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            altitudeMeters: 0, speedMps: 10, courseDegrees: 360
        )
        let blob = service.encode(sample)
        let payload = try? ScreenPayloadCodec.decode(blob!)
        guard case .compass(let data, _) = payload else {
            XCTFail("expected compass payload")
            return
        }
        XCTAssertEqual(data.magneticHeadingDegX10, 0)
    }

    func test_encode_accuracyClampsToMax() {
        let service = CompassService(provider: StubProvider())
        let sample = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            altitudeMeters: 0, speedMps: 10, courseDegrees: 0,
            horizontalAccuracyMeters: 500 // exceeds 359.9 clamp
        )
        let blob = service.encode(sample)
        let payload = try? ScreenPayloadCodec.decode(blob!)
        guard case .compass(let data, _) = payload else {
            XCTFail("expected compass payload")
            return
        }
        XCTAssertEqual(data.headingAccuracyDegX10, 3599)
    }

    func test_payloadRoundTrip() throws {
        let service = CompassService(provider: StubProvider())
        let sample = LocationSample(
            scenarioTime: 0, latitude: 48.1, longitude: 11.5,
            altitudeMeters: 520, speedMps: 15, courseDegrees: 222.3,
            horizontalAccuracyMeters: 5
        )
        let blob = try XCTUnwrap(service.encode(sample))
        let decoded = try ScreenPayloadCodec.decode(blob)
        guard case .compass(let data, _) = decoded else {
            XCTFail("expected compass payload")
            return
        }
        XCTAssertEqual(data.magneticHeadingDegX10, 2223)
        XCTAssertEqual(data.trueHeadingDegX10, 2223)
        XCTAssertEqual(data.headingAccuracyDegX10, 50)
        XCTAssertTrue(data.useTrueHeading)

        // Re-encode and verify byte-level equality.
        let reEncoded = try ScreenPayloadCodec.encode(.compass(data, flags: []))
        XCTAssertEqual(blob, reEncoded)
    }

    func test_streamReceivesEncodedPayloads() async {
        let mock = MockLocationProvider()
        let service = CompassService(provider: mock)
        service.start()

        var iterator = service.encodedPayloads.makeAsyncIterator()

        mock.emit(
            LocationSample(
                scenarioTime: 0, latitude: 0, longitude: 0,
                altitudeMeters: 0, speedMps: 10, courseDegrees: 90
            )
        )

        let blob = await iterator.next()
        XCTAssertNotNil(blob)
        guard let blob, case .compass(let data, _) = try? ScreenPayloadCodec.decode(blob) else {
            XCTFail("stream did not deliver a compass payload")
            return
        }
        XCTAssertEqual(data.magneticHeadingDegX10, 900)
        XCTAssertEqual(data.trueHeadingDegX10, 900)
        service.stop()
    }
}

/// Trivial ``LocationProvider`` used to exercise the pure transform path
/// without spinning up the forwarding task.
private final class StubProvider: LocationProvider, @unchecked Sendable {
    let samples: AsyncStream<LocationSample>
    init() {
        self.samples = AsyncStream { _ in }
    }
    func start() async {}
    func stop() async {}
}
