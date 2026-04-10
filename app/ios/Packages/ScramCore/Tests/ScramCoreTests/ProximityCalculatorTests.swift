import XCTest

@testable import ScramCore

final class ProximityCalculatorTests: XCTestCase {

    // Basel Aeschengraben area cameras
    private let cameraA = SpeedCamera(
        latitude: 47.5506, longitude: 7.5914,
        speedLimitKmh: 50, cameraType: .fixed
    )
    private let cameraB = SpeedCamera(
        latitude: 47.5525, longitude: 7.5903,
        speedLimitKmh: 30, cameraType: .redLight
    )
    private let cameraFar = SpeedCamera(
        latitude: 47.5600, longitude: 7.6000,
        speedLimitKmh: 80, cameraType: .section
    )

    func test_emptyDatabase_returnsNil() {
        let result = ProximityCalculator.findNearest(
            cameras: [],
            latitude: 47.5500, longitude: 7.5900,
            alertRadiusMeters: 500
        )
        XCTAssertNil(result)
    }

    func test_singleCamera_withinRange() {
        let result = ProximityCalculator.findNearest(
            cameras: [cameraA],
            latitude: 47.5506, longitude: 7.5914,
            alertRadiusMeters: 500
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.nearestCamera, cameraA)
        XCTAssertTrue(result?.isInAlertRange ?? false)
        XCTAssertLessThan(result?.distanceMeters ?? .infinity, 1.0)
    }

    func test_singleCamera_outsideRange() {
        // cameraFar is about 1.2 km from position
        let result = ProximityCalculator.findNearest(
            cameras: [cameraFar],
            latitude: 47.5500, longitude: 7.5900,
            alertRadiusMeters: 500
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.nearestCamera, cameraFar)
        XCTAssertFalse(result?.isInAlertRange ?? true)
        XCTAssertGreaterThan(result?.distanceMeters ?? 0, 500)
    }

    func test_multipleCameras_selectsNearest() {
        let result = ProximityCalculator.findNearest(
            cameras: [cameraA, cameraB, cameraFar],
            latitude: 47.5506, longitude: 7.5914,
            alertRadiusMeters: 500
        )
        XCTAssertNotNil(result)
        // cameraA is at the exact position
        XCTAssertEqual(result?.nearestCamera, cameraA)
        XCTAssertTrue(result?.isInAlertRange ?? false)
    }

    func test_cameraExactlyAtBoundary() {
        // Place observer such that cameraA is exactly at radius distance
        // First, find the distance to cameraA from a known point
        let distance = GeoMath.haversineMeters(
            lat1: 47.5482, lon1: 7.5899,
            lat2: cameraA.latitude, lon2: cameraA.longitude
        )
        // Use that exact distance as the alert radius
        let result = ProximityCalculator.findNearest(
            cameras: [cameraA],
            latitude: 47.5482, longitude: 7.5899,
            alertRadiusMeters: distance
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isInAlertRange ?? false, "camera exactly at boundary should be in range")
    }

    func test_multipleCameras_differentDistances() {
        // Position near cameraB
        let result = ProximityCalculator.findNearest(
            cameras: [cameraA, cameraB, cameraFar],
            latitude: 47.5525, longitude: 7.5903,
            alertRadiusMeters: 500
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.nearestCamera, cameraB)
    }
}
