import XCTest

@testable import ScramCore

/// Tests for direction-aware speed camera alerting.
/// Verifies that cameras behind the rider or on parallel roads
/// don't trigger false alerts.
final class DirectionalBlitzerTests: XCTestCase {

    // Camera at a known position (Basel Autobahn A2, heading east)
    let camera = SpeedCamera(
        latitude: 47.5600,
        longitude: 7.6000,
        speedLimitKmh: 120,
        cameraType: .fixed
    )

    // Rider position 400m west of camera
    let riderLat = 47.5600
    let riderLon = 7.5940

    // MARK: - Heading toward camera → alert

    func test_headingTowardCamera_triggersAlert() {
        // Rider heading east (90°) toward camera east of them
        let result = ProximityCalculator.findNearest(
            cameras: [camera],
            latitude: riderLat,
            longitude: riderLon,
            alertRadiusMeters: 500,
            riderHeadingDegrees: 90
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isInAlertRange)
    }

    // MARK: - Heading away from camera → no alert

    func test_headingAwayFromCamera_noAlert() {
        // Rider heading west (270°) — camera is behind them
        let result = ProximityCalculator.findNearest(
            cameras: [camera],
            latitude: riderLat,
            longitude: riderLon,
            alertRadiusMeters: 500,
            riderHeadingDegrees: 270
        )
        // Camera should be filtered out — no alert
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isInAlertRange)
    }

    // MARK: - Perpendicular heading → no alert

    func test_perpendicularHeading_noAlert() {
        // Rider heading north (0°) — camera is to the east
        let result = ProximityCalculator.findNearest(
            cameras: [camera],
            latitude: riderLat,
            longitude: riderLon,
            alertRadiusMeters: 500,
            riderHeadingDegrees: 0
        )
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isInAlertRange)
    }

    // MARK: - No heading (stationary) → alert anyway

    func test_noHeading_alertsAnyway() {
        // When heading is nil (stationary), skip direction filter
        let result = ProximityCalculator.findNearest(
            cameras: [camera],
            latitude: riderLat,
            longitude: riderLon,
            alertRadiusMeters: 500,
            riderHeadingDegrees: nil
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isInAlertRange)
    }

    // MARK: - Slight angle still alerts

    func test_slightAngle_stillAlerts() {
        // Heading ENE (70°) toward camera at ~90° — within 60° cone
        let result = ProximityCalculator.findNearest(
            cameras: [camera],
            latitude: riderLat,
            longitude: riderLon,
            alertRadiusMeters: 500,
            riderHeadingDegrees: 70
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isInAlertRange)
    }

    // MARK: - GeoMath bearing

    func test_bearing_eastward() {
        let bearing = GeoMath.bearing(
            lat1: 47.56, lon1: 7.59,
            lat2: 47.56, lon2: 7.60
        )
        // Should be roughly east (90°)
        XCTAssertEqual(bearing, 90, accuracy: 2)
    }

    func test_bearing_northward() {
        let bearing = GeoMath.bearing(
            lat1: 47.56, lon1: 7.59,
            lat2: 47.57, lon2: 7.59
        )
        // Should be roughly north (0°)
        XCTAssertEqual(bearing, 0, accuracy: 2)
    }

    func test_angleDifference_wrapsAround() {
        XCTAssertEqual(GeoMath.angleDifference(10, 350), 20, accuracy: 0.01)
        XCTAssertEqual(GeoMath.angleDifference(350, 10), 20, accuracy: 0.01)
        XCTAssertEqual(GeoMath.angleDifference(0, 180), 180, accuracy: 0.01)
        XCTAssertEqual(GeoMath.angleDifference(90, 270), 180, accuracy: 0.01)
    }
}
