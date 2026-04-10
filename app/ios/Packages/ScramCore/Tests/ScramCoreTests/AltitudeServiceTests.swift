import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class AltitudeServiceTests: XCTestCase {
    func test_ingest_emitsOnePayloadPerSample() async throws {
        let mock = MockLocationProvider()
        let service = AltitudeService(provider: mock)
        service.start()

        var iterator = service.payloads.makeAsyncIterator()

        mock.emit(
            LocationSample(scenarioTime: 0, latitude: 47.0, longitude: 7.0,
                           altitudeMeters: 260, speedMps: 0)
        )
        mock.emit(
            LocationSample(scenarioTime: 1, latitude: 47.0001, longitude: 7.0,
                           altitudeMeters: 280, speedMps: 11)
        )

        let first = await iterator.next()
        let second = await iterator.next()
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)

        // Decode the second payload
        guard let second,
              case .altitude(let alt, _) = try? ScreenPayloadCodec.decode(second) else {
            XCTFail("expected altitude payload")
            return
        }
        XCTAssertEqual(alt.sampleCount, 2)
        XCTAssertEqual(alt.currentAltitudeM, 280)
        XCTAssertEqual(alt.profile[0], 260)
        XCTAssertEqual(alt.profile[1], 280)

        service.stop()
    }

    func test_payloads_decodBackToExpectedData() async throws {
        let mock = MockLocationProvider()
        let service = AltitudeService(provider: mock)
        service.start()

        var iterator = service.payloads.makeAsyncIterator()

        // Climb from 500 to 510 (10m ascent, > 1m jitter threshold)
        mock.emit(
            LocationSample(scenarioTime: 0, latitude: 47, longitude: 7,
                           altitudeMeters: 500, speedMps: 10)
        )
        mock.emit(
            LocationSample(scenarioTime: 1, latitude: 47, longitude: 7,
                           altitudeMeters: 510, speedMps: 10)
        )
        mock.emit(
            LocationSample(scenarioTime: 2, latitude: 47, longitude: 7,
                           altitudeMeters: 505, speedMps: 10)
        )

        // Consume all 3
        _ = await iterator.next()
        _ = await iterator.next()
        let thirdBlob = await iterator.next()

        guard let thirdBlob,
              case .altitude(let data, _) = try ScreenPayloadCodec.decode(thirdBlob) else {
            XCTFail("expected altitude payload")
            return
        }

        XCTAssertEqual(data.sampleCount, 3)
        XCTAssertEqual(data.currentAltitudeM, 505)
        XCTAssertEqual(data.totalAscentM, 10)
        XCTAssertEqual(data.totalDescentM, 5)

        service.stop()
    }

    func test_reset_clearsBuffer() async throws {
        let mock = MockLocationProvider()
        let service = AltitudeService(provider: mock)
        service.start()

        var iterator = service.payloads.makeAsyncIterator()

        mock.emit(
            LocationSample(scenarioTime: 0, latitude: 47, longitude: 7,
                           altitudeMeters: 500, speedMps: 0)
        )
        _ = await iterator.next()

        let snapBefore = service.currentSnapshot
        XCTAssertEqual(snapBefore.sampleCount, 1)

        service.reset()
        let snapAfter = service.currentSnapshot
        XCTAssertEqual(snapAfter.sampleCount, 0)

        service.stop()
    }

    func test_doubleStart_isIdempotent() {
        let mock = MockLocationProvider()
        let service = AltitudeService(provider: mock)
        service.start()
        service.start() // must not crash
        service.stop()
    }
}
