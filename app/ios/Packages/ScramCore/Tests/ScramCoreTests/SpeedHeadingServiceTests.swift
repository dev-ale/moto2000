import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class SpeedHeadingServiceTests: XCTestCase {
    func test_encode_convertsSpeedMpsToKmhX10() {
        let service = SpeedHeadingService(provider: StubProvider())
        let sample = LocationSample(
            scenarioTime: 0,
            latitude: 0,
            longitude: 0,
            altitudeMeters: 260,
            speedMps: 10, // 36.0 km/h -> 360
            courseDegrees: 90
        )
        let blob = service.encode(sample)
        let payload = try? ScreenPayloadCodec.decode(blob!)
        guard case .speedHeading(let data, _) = payload else {
            XCTFail("wrong payload")
            return
        }
        XCTAssertEqual(data.speedKmhX10, 360)
        XCTAssertEqual(data.headingDegX10, 900)
        XCTAssertEqual(data.altitudeMeters, 260)
        XCTAssertEqual(data.temperatureCelsiusX10, 0)
    }

    func test_encode_negativeSpeedBecomesZero() {
        let service = SpeedHeadingService(provider: StubProvider())
        let sample = LocationSample(
            scenarioTime: 0,
            latitude: 0,
            longitude: 0,
            altitudeMeters: 0,
            speedMps: -1,
            courseDegrees: 45
        )
        let blob = service.encode(sample)
        let payload = try? ScreenPayloadCodec.decode(blob!)
        guard case .speedHeading(let data, _) = payload else {
            XCTFail()
            return
        }
        XCTAssertEqual(data.speedKmhX10, 0)
    }

    func test_encode_clampsExcessiveSpeed() {
        let service = SpeedHeadingService(provider: StubProvider())
        let sample = LocationSample(
            scenarioTime: 0,
            latitude: 0,
            longitude: 0,
            altitudeMeters: 0,
            speedMps: 1000, // 3600 km/h — way over
            courseDegrees: 0
        )
        let blob = service.encode(sample)
        let payload = try? ScreenPayloadCodec.decode(blob!)
        guard case .speedHeading(let data, _) = payload else {
            XCTFail()
            return
        }
        XCTAssertEqual(data.speedKmhX10, 3000)
    }

    func test_encode_unknownHeadingReusesPrevious() {
        let service = SpeedHeadingService(provider: StubProvider())
        let first = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            altitudeMeters: 0, speedMps: 5, courseDegrees: 150
        )
        _ = service.encode(first)
        let second = LocationSample(
            scenarioTime: 1, latitude: 0, longitude: 0,
            altitudeMeters: 0, speedMps: 5, courseDegrees: -1
        )
        let blob = service.encode(second)
        let payload = try? ScreenPayloadCodec.decode(blob!)
        guard case .speedHeading(let data, _) = payload else {
            XCTFail()
            return
        }
        XCTAssertEqual(data.headingDegX10, 1500)
    }

    func test_encode_headingWrapsWith360() {
        let service = SpeedHeadingService(provider: StubProvider())
        let sample = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            altitudeMeters: 0, speedMps: 5, courseDegrees: 360
        )
        let blob = service.encode(sample)
        let payload = try? ScreenPayloadCodec.decode(blob!)
        guard case .speedHeading(let data, _) = payload else {
            XCTFail()
            return
        }
        XCTAssertEqual(data.headingDegX10, 0)
    }

    func test_encode_clampsAltitudeToInt16Range() {
        let service = SpeedHeadingService(provider: StubProvider())
        let tooHigh = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            altitudeMeters: 20_000, speedMps: 0, courseDegrees: 0
        )
        let tooLow = LocationSample(
            scenarioTime: 0, latitude: 0, longitude: 0,
            altitudeMeters: -10_000, speedMps: 0, courseDegrees: 0
        )
        let highPayload = try? ScreenPayloadCodec.decode(service.encode(tooHigh)!)
        let lowPayload = try? ScreenPayloadCodec.decode(service.encode(tooLow)!)
        guard
            case .speedHeading(let highData, _) = highPayload,
            case .speedHeading(let lowData, _) = lowPayload
        else {
            XCTFail()
            return
        }
        XCTAssertEqual(highData.altitudeMeters, 9000)
        XCTAssertEqual(lowData.altitudeMeters, -500)
    }

    func test_streamReceivesEncodedPayloads() async {
        let mock = MockLocationProvider()
        let service = SpeedHeadingService(provider: mock)
        service.start()

        var iterator = service.encodedPayloads.makeAsyncIterator()

        mock.emit(
            LocationSample(
                scenarioTime: 0, latitude: 0, longitude: 0,
                altitudeMeters: 260, speedMps: 10, courseDegrees: 180
            )
        )

        let blob = await iterator.next()
        XCTAssertNotNil(blob)
        guard let blob, case .speedHeading(let data, _) = try? ScreenPayloadCodec.decode(blob) else {
            XCTFail("stream did not deliver a speedHeading payload")
            return
        }
        XCTAssertEqual(data.speedKmhX10, 360)
        XCTAssertEqual(data.headingDegX10, 1800)
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
