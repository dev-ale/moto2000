import XCTest
import BLEProtocol
import RideSimulatorKit

@testable import ScramCore

/// End-to-end test that replays the Basel city loop GPX with a synthetic
/// camera placed along the route. Asserts the alert fires at the expected
/// location samples and clears when the rider moves away.
///
/// The Basel city loop GPX has waypoints from (47.5482, 7.5899) going
/// north along Aeschengraben then turning. We place a camera at
/// (47.5506, 7.5914) which is near the 5th-6th waypoints.
final class BlitzerIntegrationTests: XCTestCase {

    /// Camera placed along the Basel city loop route at a position
    /// the rider passes through around the 40-50s mark.
    private let syntheticCamera = SpeedCamera(
        latitude: 47.5506,
        longitude: 7.5914,
        speedLimitKmh: 50,
        cameraType: .fixed
    )

    /// GPX waypoints from the Basel city loop, extracted for direct replay.
    private let routeWaypoints: [(time: Double, lat: Double, lon: Double, speed: Double)] = [
        (0,   47.5482, 7.5899, 8.0),
        (10,  47.5486, 7.5902, 8.0),
        (20,  47.5491, 7.5905, 8.0),
        (30,  47.5496, 7.5908, 8.0),
        (40,  47.5501, 7.5911, 8.0),
        (50,  47.5506, 7.5914, 8.0),  // near camera
        (60,  47.5510, 7.5917, 8.0),  // near camera
        (70,  47.5515, 7.5915, 8.0),
        (80,  47.5520, 7.5910, 8.0),
        (90,  47.5525, 7.5903, 8.0),
        (100, 47.5524, 7.5895, 8.0),
        (110, 47.5518, 7.5892, 8.0),
        (120, 47.5511, 7.5890, 8.0),
        (130, 47.5504, 7.5891, 8.0),
        (140, 47.5497, 7.5893, 8.0),
        (150, 47.5490, 7.5895, 8.0),
        (160, 47.5484, 7.5897, 8.0),
        (170, 47.5482, 7.5899, 8.0),
    ]

    func test_replayBaselCityLoop_alertFiresNearCamera() async throws {
        let mockLocation = MockLocationProvider()
        let db = InMemorySpeedCameraDatabase(cameras: [syntheticCamera])
        let settings = BlitzerSettings(alertRadiusMeters: 200)
        let service = BlitzerAlertService(
            locationProvider: mockLocation,
            database: db,
            settings: settings
        )
        await service.start()

        var received: [Data] = []
        let collectorTask = Task { () -> [Data] in
            var out: [Data] = []
            for await blob in service.payloads {
                out.append(blob)
            }
            return out
        }

        // Replay all waypoints
        for wp in routeWaypoints {
            mockLocation.emit(LocationSample(
                scenarioTime: wp.time,
                latitude: wp.lat,
                longitude: wp.lon,
                speedMps: wp.speed
            ))
            // Small delay to let the actor process
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        await service.stop()
        await mockLocation.stop()

        received = await collectorTask.value

        // We expect at least some alert payloads (when near camera)
        // and then a clear when moving away.
        XCTAssertGreaterThanOrEqual(received.count, 2, "should have at least alert + clear")

        // Check that some payloads have ALERT set
        var hasAlert = false
        var hasClear = false
        for blob in received {
            let payload = try ScreenPayloadCodec.decode(blob)
            guard case .blitzer(_, let flags) = payload else {
                XCTFail("expected blitzer payload"); continue
            }
            if flags.contains(.alert) {
                hasAlert = true
            } else {
                hasClear = true
            }
        }

        XCTAssertTrue(hasAlert, "must have at least one ALERT payload")
        XCTAssertTrue(hasClear, "must have at least one CLEAR payload after leaving range")

        // The last payload (after moving away) should have ALERT cleared
        if let lastBlob = received.last {
            let lastPayload = try ScreenPayloadCodec.decode(lastBlob)
            guard case .blitzer(_, let lastFlags) = lastPayload else {
                XCTFail("expected blitzer"); return
            }
            XCTAssertFalse(lastFlags.contains(.alert), "last payload should clear ALERT")
        }
    }
}
