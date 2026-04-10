import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

final class BlitzerAlertServiceTests: XCTestCase {

    // Camera on the route at 47.5506, 7.5914
    private let cameraOnRoute = SpeedCamera(
        latitude: 47.5506, longitude: 7.5914,
        speedLimitKmh: 50, cameraType: .fixed
    )
    // Camera far away
    private let cameraFarAway = SpeedCamera(
        latitude: 47.5800, longitude: 7.6200,
        speedLimitKmh: 80, cameraType: .section
    )

    func test_noAlert_whenFarFromCameras() async throws {
        let mockLocation = MockLocationProvider()
        let db = InMemorySpeedCameraDatabase(cameras: [cameraFarAway])
        let service = BlitzerAlertService(
            locationProvider: mockLocation,
            database: db,
            settings: BlitzerSettings(alertRadiusMeters: 500)
        )
        await service.start()

        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in service.payloads {
                out.append(blob)
                if out.count >= 1 { return out }
            }
            return out
        }

        // Emit a location far from any camera
        mockLocation.emit(LocationSample(
            scenarioTime: 0,
            latitude: 47.5482, longitude: 7.5899,
            speedMps: 10
        ))

        // Give it a moment, then stop
        try await Task.sleep(nanoseconds: 100_000_000)
        await service.stop()
        await mockLocation.stop()

        let received = await collectorTask.value
        XCTAssertTrue(received.isEmpty, "no alert should fire when far from cameras")
    }

    func test_alertFires_whenApproachingCamera() async throws {
        let mockLocation = MockLocationProvider()
        let db = InMemorySpeedCameraDatabase(cameras: [cameraOnRoute])
        let service = BlitzerAlertService(
            locationProvider: mockLocation,
            database: db,
            settings: BlitzerSettings(alertRadiusMeters: 500)
        )
        await service.start()

        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in service.payloads {
                out.append(blob)
                if out.count >= 1 { return out }
            }
            return out
        }

        // Emit a location within 500m of cameraOnRoute
        mockLocation.emit(LocationSample(
            scenarioTime: 1,
            latitude: 47.5506, longitude: 7.5914,
            speedMps: 14.0 // ~50 km/h
        ))

        try await Task.sleep(nanoseconds: 200_000_000)
        await service.stop()
        await mockLocation.stop()

        let received = await collectorTask.value
        XCTAssertEqual(received.count, 1, "alert should fire when near camera")

        let payload = try ScreenPayloadCodec.decode(received[0])
        guard case .blitzer(let blitzer, let flags) = payload else {
            XCTFail("expected blitzer payload"); return
        }
        XCTAssertTrue(flags.contains(.alert), "ALERT flag must be set")
        XCTAssertEqual(blitzer.cameraType, .fixed)
        XCTAssertEqual(blitzer.speedLimitKmh, 50)
    }

    func test_alertClears_whenMovingAway() async throws {
        let mockLocation = MockLocationProvider()
        let db = InMemorySpeedCameraDatabase(cameras: [cameraOnRoute])
        let service = BlitzerAlertService(
            locationProvider: mockLocation,
            database: db,
            settings: BlitzerSettings(alertRadiusMeters: 500)
        )
        await service.start()

        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in service.payloads {
                out.append(blob)
                if out.count >= 2 { return out }
            }
            return out
        }

        // First: approach camera (within range)
        mockLocation.emit(LocationSample(
            scenarioTime: 1,
            latitude: 47.5506, longitude: 7.5914,
            speedMps: 14.0
        ))

        try await Task.sleep(nanoseconds: 100_000_000)

        // Second: move away from camera (far from any camera)
        mockLocation.emit(LocationSample(
            scenarioTime: 2,
            latitude: 47.5300, longitude: 7.5700,
            speedMps: 14.0
        ))

        try await Task.sleep(nanoseconds: 200_000_000)
        await service.stop()
        await mockLocation.stop()

        let received = await collectorTask.value
        XCTAssertEqual(received.count, 2, "should get alert + clear")

        // First payload: ALERT set
        let p1 = try ScreenPayloadCodec.decode(received[0])
        guard case .blitzer(_, let f1) = p1 else {
            XCTFail("expected blitzer"); return
        }
        XCTAssertTrue(f1.contains(.alert), "first payload must have ALERT set")

        // Second payload: ALERT cleared
        let p2 = try ScreenPayloadCodec.decode(received[1])
        guard case .blitzer(_, let f2) = p2 else {
            XCTFail("expected blitzer"); return
        }
        XCTAssertFalse(f2.contains(.alert), "second payload must have ALERT cleared")
    }

    func test_noDoubleAlert_whenStayingNearCamera() async throws {
        let mockLocation = MockLocationProvider()
        let db = InMemorySpeedCameraDatabase(cameras: [cameraOnRoute])
        let service = BlitzerAlertService(
            locationProvider: mockLocation,
            database: db,
            settings: BlitzerSettings(alertRadiusMeters: 500)
        )
        await service.start()

        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in service.payloads {
                out.append(blob)
                // Give time for multiple
                if out.count >= 3 { return out }
            }
            return out
        }

        // Multiple samples near the same camera
        for i in 0..<3 {
            mockLocation.emit(LocationSample(
                scenarioTime: Double(i),
                latitude: 47.5506 + Double(i) * 0.0001,
                longitude: 7.5914,
                speedMps: 14.0
            ))
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        await service.stop()
        await mockLocation.stop()

        let received = await collectorTask.value
        // Each location near camera emits an alert (updating distance)
        XCTAssertEqual(received.count, 3)
        // All should have ALERT set
        for blob in received {
            let payload = try ScreenPayloadCodec.decode(blob)
            guard case .blitzer(_, let flags) = payload else {
                XCTFail("expected blitzer"); continue
            }
            XCTAssertTrue(flags.contains(.alert))
        }
    }
}
