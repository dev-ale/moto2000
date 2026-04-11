import XCTest
@testable import ScramCore

final class GeoMathTests: XCTestCase {

    // MARK: - haversineMeters

    /// Same point → 0 distance.
    func test_haversine_samePoint_returnsZero() {
        let d = GeoMath.haversineMeters(
            lat1: 47.5596, lon1: 7.5886,
            lat2: 47.5596, lon2: 7.5886
        )
        XCTAssertEqual(d, 0, accuracy: 1e-9)
    }

    /// Basel SBB → Basel Münster (known ~600 m apart).
    func test_haversine_baselSBBtoMuenster() {
        let d = GeoMath.haversineMeters(
            lat1: 47.5476, lon1: 7.5897,  // Basel SBB
            lat2: 47.5565, lon2: 7.5926   // Basel Münster
        )
        // Google Maps: ~1000 m. Allow ±50 m for coordinate rounding.
        XCTAssertEqual(d, 1000, accuracy: 50)
    }

    /// Zürich HB → Basel SBB (~74 km).
    func test_haversine_zurichToBasel() {
        let d = GeoMath.haversineMeters(
            lat1: 47.3769, lon1: 8.5417,  // Zürich HB
            lat2: 47.5476, lon2: 7.5897   // Basel SBB
        )
        XCTAssertEqual(d, 74_040, accuracy: 500)
    }

    /// Equator, one degree of longitude ≈ 111.195 km (for R=6371 km).
    func test_haversine_equatorOneDegLon() {
        let d = GeoMath.haversineMeters(
            lat1: 0, lon1: 0,
            lat2: 0, lon2: 1
        )
        XCTAssertEqual(d, 111_195, accuracy: 10)
    }

    /// North pole to south pole ≈ half circumference ≈ 20 015 km.
    func test_haversine_poleToPoleDiameter() {
        let d = GeoMath.haversineMeters(
            lat1: 90, lon1: 0,
            lat2: -90, lon2: 0
        )
        XCTAssertEqual(d, 20_015_000, accuracy: 1_000)
    }

    // MARK: - bearing

    /// Due north: same longitude, increasing latitude.
    func test_bearing_dueNorth() {
        let b = GeoMath.bearing(
            lat1: 47.0, lon1: 7.0,
            lat2: 48.0, lon2: 7.0
        )
        XCTAssertEqual(b, 0, accuracy: 0.5)
    }

    /// Due east: same latitude, increasing longitude.
    func test_bearing_dueEast() {
        let b = GeoMath.bearing(
            lat1: 47.0, lon1: 7.0,
            lat2: 47.0, lon2: 8.0
        )
        XCTAssertEqual(b, 90, accuracy: 1.0)
    }

    /// Due south.
    func test_bearing_dueSouth() {
        let b = GeoMath.bearing(
            lat1: 48.0, lon1: 7.0,
            lat2: 47.0, lon2: 7.0
        )
        XCTAssertEqual(b, 180, accuracy: 0.5)
    }

    /// Due west.
    func test_bearing_dueWest() {
        let b = GeoMath.bearing(
            lat1: 47.0, lon1: 8.0,
            lat2: 47.0, lon2: 7.0
        )
        XCTAssertEqual(b, 270, accuracy: 1.0)
    }

    /// Same point: bearing is 0 by convention (atan2(0,0)).
    func test_bearing_samePoint() {
        let b = GeoMath.bearing(
            lat1: 47.0, lon1: 7.0,
            lat2: 47.0, lon2: 7.0
        )
        XCTAssertEqual(b, 0, accuracy: 1e-9)
    }

    // MARK: - angleDifference

    func test_angleDifference_zero() {
        XCTAssertEqual(GeoMath.angleDifference(90, 90), 0, accuracy: 1e-9)
    }

    func test_angleDifference_simple() {
        XCTAssertEqual(GeoMath.angleDifference(10, 350), 20, accuracy: 1e-9)
    }

    func test_angleDifference_opposite() {
        XCTAssertEqual(GeoMath.angleDifference(0, 180), 180, accuracy: 1e-9)
    }

    func test_angleDifference_wrapAround() {
        XCTAssertEqual(GeoMath.angleDifference(5, 355), 10, accuracy: 1e-9)
    }

    func test_angleDifference_negativeInputs() {
        XCTAssertEqual(GeoMath.angleDifference(-10, 10), 20, accuracy: 1e-9)
    }

    func test_angleDifference_largeValues() {
        XCTAssertEqual(GeoMath.angleDifference(370, 10), 0, accuracy: 1e-9)
    }
}
