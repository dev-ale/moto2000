import XCTest

@testable import BLEProtocol

final class NavDataTests: XCTestCase {
    private func sample() -> NavData {
        NavData(
            latitudeE7: 475_482_000,
            longitudeE7: 75_899_000,
            speedKmhX10: 453,
            headingDegX10: 1827,
            distanceToManeuverMeters: 320,
            maneuver: .straight,
            streetName: "Aeschengraben",
            etaMinutes: 18,
            remainingKmX10: 74
        )
    }

    func test_encode_matchesExpectedSize() throws {
        let encoded = try sample().encode()
        XCTAssertEqual(encoded.count, NavData.encodedSize)
    }

    func test_encodeDecode_roundTrip() throws {
        let original = sample()
        let bytes = try original.encode()
        let decoded = try NavData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encode_rejectsOutOfRangeHeading() {
        var nav = sample()
        nav.headingDegX10 = 3600
        XCTAssertThrowsError(try nav.encode()) { error in
            XCTAssertEqual(error as? BLEProtocolError, .valueOutOfRange(field: "nav.headingDegX10"))
        }
    }

    func test_encode_rejectsOutOfRangeSpeed() {
        var nav = sample()
        nav.speedKmhX10 = 3001
        XCTAssertThrowsError(try nav.encode()) { error in
            XCTAssertEqual(error as? BLEProtocolError, .valueOutOfRange(field: "nav.speedKmhX10"))
        }
    }

    func test_encode_rejectsOversizedStreetName() {
        var nav = sample()
        nav.streetName = String(repeating: "X", count: 32)  // no room for terminator
        XCTAssertThrowsError(try nav.encode())
    }

    func test_maneuverTypeCoversAllSpecValues() {
        XCTAssertEqual(ManeuverType.allCases.count, 16)
    }
}
