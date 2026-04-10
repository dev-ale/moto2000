import XCTest

@testable import ScramCore

final class InMemorySpeedCameraDatabaseTests: XCTestCase {

    private let cameras = [
        SpeedCamera(latitude: 47.5506, longitude: 7.5914, speedLimitKmh: 50, cameraType: .fixed),
        SpeedCamera(latitude: 47.5525, longitude: 7.5903, speedLimitKmh: 30, cameraType: .redLight),
        SpeedCamera(latitude: 47.5600, longitude: 7.6000, speedLimitKmh: 80, cameraType: .section),
    ]

    func test_queryCamerasNear_returnsOnlyWithinRadius() async throws {
        let db = InMemorySpeedCameraDatabase(cameras: cameras)
        // Position near the first two cameras (within ~300m)
        let nearby = try await db.camerasNear(
            latitude: 47.5510,
            longitude: 7.5910,
            radiusMeters: 500
        )
        // First two should be within 500m, third is ~1.2km away
        XCTAssertEqual(nearby.count, 2)
        XCTAssertTrue(nearby.contains(cameras[0]))
        XCTAssertTrue(nearby.contains(cameras[1]))
        XCTAssertFalse(nearby.contains(cameras[2]))
    }

    func test_queryCamerasNear_emptyDatabase() async throws {
        let db = InMemorySpeedCameraDatabase(cameras: [])
        let nearby = try await db.camerasNear(
            latitude: 47.5500,
            longitude: 7.5900,
            radiusMeters: 1000
        )
        XCTAssertTrue(nearby.isEmpty)
    }

    func test_queryCamerasNear_verySmallRadius() async throws {
        let db = InMemorySpeedCameraDatabase(cameras: cameras)
        // 1 meter radius — no camera should be that close unless exact match
        let nearby = try await db.camerasNear(
            latitude: 47.5510,
            longitude: 7.5910,
            radiusMeters: 1
        )
        XCTAssertTrue(nearby.isEmpty)
    }

    func test_queryCamerasNear_largeRadius_returnsAll() async throws {
        let db = InMemorySpeedCameraDatabase(cameras: cameras)
        let nearby = try await db.camerasNear(
            latitude: 47.5510,
            longitude: 7.5910,
            radiusMeters: 50_000
        )
        XCTAssertEqual(nearby.count, cameras.count)
    }
}
