import XCTest
import RideSimulatorKit

@testable import ScramCore

final class RealLocationProviderTests: XCTestCase {
    func test_start_requestsAuthorizationWhenNotDetermined() async {
        let fake = FakeLocationManaging()
        fake.authorizationStatus = .notDetermined
        let provider = RealLocationProvider(manager: fake)
        await provider.start()
        XCTAssertEqual(fake.requestWhenInUseCount, 1)
        XCTAssertEqual(fake.startCount, 1)
    }

    func test_start_doesNotRequestAuthWhenAlreadyAuthorized() async {
        let fake = FakeLocationManaging()
        fake.authorizationStatus = .authorizedWhenInUse
        let provider = RealLocationProvider(manager: fake)
        await provider.start()
        XCTAssertEqual(fake.requestWhenInUseCount, 0)
        XCTAssertEqual(fake.startCount, 1)
    }

    func test_deliveredFixesArriveOnStream() async throws {
        let fake = FakeLocationManaging()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let provider = RealLocationProvider(manager: fake, startTime: start)
        await provider.start()

        let stream = provider.samples
        var iterator = stream.makeAsyncIterator()

        let fixes = [
            LocationManagingFix(
                latitude: 47.5482,
                longitude: 7.5899,
                altitudeMeters: 260,
                speedMps: 12.5,
                courseDegrees: 90,
                horizontalAccuracyMeters: 5,
                timestamp: start.addingTimeInterval(10)
            ),
            LocationManagingFix(
                latitude: 47.5486,
                longitude: 7.5902,
                altitudeMeters: 261,
                speedMps: 13.0,
                courseDegrees: 95,
                horizontalAccuracyMeters: 5,
                timestamp: start.addingTimeInterval(20)
            ),
        ]
        fake.deliver(fixes)

        let firstOptional = await iterator.next()
        let first = try XCTUnwrap(firstOptional)
        XCTAssertEqual(first.latitude, 47.5482, accuracy: 1e-6)
        XCTAssertEqual(first.scenarioTime, 10, accuracy: 1e-6)
        XCTAssertEqual(first.speedMps, 12.5, accuracy: 1e-6)
        XCTAssertEqual(first.courseDegrees, 90, accuracy: 1e-6)

        let secondOptional = await iterator.next()
        let second = try XCTUnwrap(secondOptional)
        XCTAssertEqual(second.latitude, 47.5486, accuracy: 1e-6)
        XCTAssertEqual(second.scenarioTime, 20, accuracy: 1e-6)
    }

    func test_stop_terminatesStream() async {
        let fake = FakeLocationManaging()
        let provider = RealLocationProvider(manager: fake)
        await provider.start()
        let stream = provider.samples
        await provider.stop()
        XCTAssertEqual(fake.stopCount, 1)

        var iterator = stream.makeAsyncIterator()
        let next = await iterator.next()
        XCTAssertNil(next, "stream should be terminated after stop()")
    }
}
