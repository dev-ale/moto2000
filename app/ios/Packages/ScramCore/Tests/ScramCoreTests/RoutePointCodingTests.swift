import Foundation
import XCTest

@testable import ScramCore

final class RoutePointCodingTests: XCTestCase {

    // MARK: - Round-trip with altitude and speed

    func test_routePoint_withAltitudeAndSpeed_roundTrips() throws {
        let original = RoutePoint(latitude: 47.56, longitude: 7.59, altitude: 320.5, speed: 15.3)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoutePoint.self, from: data)

        XCTAssertEqual(decoded.latitude, 47.56, accuracy: 0.0001)
        XCTAssertEqual(decoded.longitude, 7.59, accuracy: 0.0001)
        XCTAssertEqual(decoded.altitude, 320.5)
        XCTAssertEqual(decoded.speed, 15.3)
    }

    // MARK: - Backward compatibility

    func test_routePoint_decodesWithoutAltitudeAndSpeed() throws {
        // Simulate a JSON saved before altitude/speed fields existed
        let json = """
        {"latitude": 47.56, "longitude": 7.59}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(RoutePoint.self, from: data)

        XCTAssertEqual(decoded.latitude, 47.56, accuracy: 0.0001)
        XCTAssertEqual(decoded.longitude, 7.59, accuracy: 0.0001)
        XCTAssertNil(decoded.altitude)
        XCTAssertNil(decoded.speed)
    }

    // MARK: - Array backward compatibility

    func test_routePointArray_decodesLegacyFormat() throws {
        let json = """
        [
            {"latitude": 47.56, "longitude": 7.59},
            {"latitude": 47.57, "longitude": 7.60}
        ]
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode([RoutePoint].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertNil(decoded[0].altitude)
        XCTAssertNil(decoded[0].speed)
        XCTAssertNil(decoded[1].altitude)
        XCTAssertNil(decoded[1].speed)
    }

    // MARK: - Nil fields encoded correctly

    func test_routePoint_withNilFields_roundTrips() throws {
        let original = RoutePoint(latitude: 47.56, longitude: 7.59)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoutePoint.self, from: data)

        XCTAssertEqual(decoded.latitude, original.latitude)
        XCTAssertEqual(decoded.longitude, original.longitude)
        XCTAssertNil(decoded.altitude)
        XCTAssertNil(decoded.speed)
    }
}
