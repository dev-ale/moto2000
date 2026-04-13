import XCTest

@testable import BLEProtocol

final class WeatherDataTests: XCTestCase {
    func test_encode_matchesExpectedSize() throws {
        let data = WeatherData(
            condition: .clear,
            temperatureCelsiusX10: 220,
            highCelsiusX10: 250,
            lowCelsiusX10: 130,
            locationName: "Basel"
        )
        let encoded = try data.encode()
        XCTAssertEqual(encoded.count, WeatherData.encodedSize)
    }

    func test_encode_littleEndianLayout() throws {
        // condition=0x02 (rain), precip=0xFF (none), temp=145(0x91),
        // high=170(0xAA), low=110(0x6E), location="Paris"
        let data = WeatherData(
            condition: .rain,
            temperatureCelsiusX10: 145,
            highCelsiusX10: 170,
            lowCelsiusX10: 110,
            locationName: "Paris"
        )
        let bytes = try data.encode()
        var expected: [UInt8] = [
            0x02,        // condition
            0xFF,        // precip_minutes_until (none)
            0x91, 0x00,  // temp 145 LE
            0xAA, 0x00,  // high 170 LE
            0x6E, 0x00,  // low 110 LE
            // location "Paris" + 15 zero bytes
            0x50, 0x61, 0x72, 0x69, 0x73,
        ]
        expected.append(contentsOf: Array(repeating: 0, count: 15))
        XCTAssertEqual(Array(bytes), expected)
    }

    func test_encodeDecode_roundTrip_allConditions() throws {
        for condition in WeatherConditionWire.allCases {
            let original = WeatherData(
                condition: condition,
                temperatureCelsiusX10: 200,
                highCelsiusX10: 250,
                lowCelsiusX10: 100,
                locationName: "City\(condition.rawValue)"
            )
            let bytes = try original.encode()
            let decoded = try WeatherData.decode(bytes)
            XCTAssertEqual(decoded, original, "roundtrip failed for \(condition)")
        }
    }

    func test_encodeDecode_roundTrip_negativeTemperatures() throws {
        let original = WeatherData(
            condition: .snow,
            temperatureCelsiusX10: -35,
            highCelsiusX10: 10,
            lowCelsiusX10: -85,
            locationName: "Gotthard"
        )
        let bytes = try original.encode()
        let decoded = try WeatherData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encode_rejectsTemperatureAboveMax() {
        let data = WeatherData(
            condition: .clear,
            temperatureCelsiusX10: 601,
            highCelsiusX10: 0,
            lowCelsiusX10: 0,
            locationName: "X"
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "weather.temperatureCelsiusX10")
            )
        }
    }

    func test_encode_rejectsTemperatureBelowMin() {
        let data = WeatherData(
            condition: .clear,
            temperatureCelsiusX10: -501,
            highCelsiusX10: 0,
            lowCelsiusX10: 0,
            locationName: "X"
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "weather.temperatureCelsiusX10")
            )
        }
    }

    func test_encode_rejectsHighOutOfRange() {
        let data = WeatherData(
            condition: .clear,
            temperatureCelsiusX10: 0,
            highCelsiusX10: 700,
            lowCelsiusX10: 0,
            locationName: "X"
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "weather.highCelsiusX10")
            )
        }
    }

    func test_encode_rejectsLowOutOfRange() {
        let data = WeatherData(
            condition: .clear,
            temperatureCelsiusX10: 0,
            highCelsiusX10: 0,
            lowCelsiusX10: -600,
            locationName: "X"
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "weather.lowCelsiusX10")
            )
        }
    }

    func test_encode_rejectsLocationNameWithoutTerminatorRoom() {
        // 20 bytes = no room for terminator inside the 20-byte field.
        let data = WeatherData(
            condition: .clear,
            temperatureCelsiusX10: 0,
            highCelsiusX10: 0,
            lowCelsiusX10: 0,
            locationName: String(repeating: "A", count: 20)
        )
        XCTAssertThrowsError(try data.encode())
    }

    func test_decode_rejectsWrongBodySize() {
        let tooShort = Data(repeating: 0, count: WeatherData.encodedSize - 1)
        XCTAssertThrowsError(try WeatherData.decode(tooShort)) { error in
            guard case let .bodyLengthMismatch(screen, expected, actual) = (error as? BLEProtocolError) else {
                XCTFail("expected bodyLengthMismatch, got \(error)")
                return
            }
            XCTAssertEqual(screen, .weather)
            XCTAssertEqual(expected, WeatherData.encodedSize)
            XCTAssertEqual(actual, WeatherData.encodedSize - 1)
        }
    }

    func test_decode_rejectsUnknownConditionByte() {
        var bytes = [UInt8](repeating: 0, count: WeatherData.encodedSize)
        bytes[0] = 0x09  // out of range
        // place a null terminator so we don't trip unterminatedString first
        bytes[8] = 0x00
        XCTAssertThrowsError(try WeatherData.decode(Data(bytes))) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "weather.condition")
            )
        }
    }

    func test_decode_acceptsAnyPrecipValue() throws {
        // Byte 1 used to be "reserved (=0)"; it now carries
        // precip_minutes_until, so any value is valid.
        var bytes = [UInt8](repeating: 0, count: WeatherData.encodedSize)
        bytes[0] = 0x00   // condition = clear
        bytes[1] = 0x2A   // 42 minutes until rain
        let decoded = try WeatherData.decode(Data(bytes))
        XCTAssertEqual(decoded.precipMinutesUntil, 42)
    }

    func test_screenPayloadCodec_roundTripsWeather() throws {
        let original = ScreenPayload.weather(
            WeatherData(
                condition: .thunderstorm,
                temperatureCelsiusX10: 180,
                highCelsiusX10: 220,
                lowCelsiusX10: 140,
                locationName: "Basel"
            ),
            flags: [.nightMode]
        )
        let encoded = try ScreenPayloadCodec.encode(original)
        // header (8) + body (28)
        XCTAssertEqual(encoded.count, 8 + WeatherData.encodedSize)
        let decoded = try ScreenPayloadCodec.decode(encoded)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.screenID, .weather)
    }
}
