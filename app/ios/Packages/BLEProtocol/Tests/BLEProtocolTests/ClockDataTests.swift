import XCTest

@testable import BLEProtocol

final class ClockDataTests: XCTestCase {
    func test_encode_matchesExpectedSize() throws {
        let clock = ClockData(unixTime: 1_738_339_200, tzOffsetMinutes: 60, is24Hour: true)
        let encoded = try clock.encode()
        XCTAssertEqual(encoded.count, ClockData.encodedSize)
    }

    func test_encodeDecode_roundTrip() throws {
        let original = ClockData(unixTime: 1_700_000_000, tzOffsetMinutes: -300, is24Hour: false)
        let bytes = try original.encode()
        let decoded = try ClockData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encode_rejectsOutOfRangeTimezone() {
        var clock = ClockData(unixTime: 0, tzOffsetMinutes: 0, is24Hour: true)
        clock.tzOffsetMinutes = 900
        XCTAssertThrowsError(try clock.encode()) { error in
            XCTAssertEqual(error as? BLEProtocolError, .valueOutOfRange(field: "clock.tzOffsetMinutes"))
        }
    }
}
