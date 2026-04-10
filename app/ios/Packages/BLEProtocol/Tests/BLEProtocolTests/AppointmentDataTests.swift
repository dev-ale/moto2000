import XCTest

@testable import BLEProtocol

final class AppointmentDataTests: XCTestCase {
    func test_encodedSizeMatchesSpec() {
        XCTAssertEqual(AppointmentData.encodedSize, 60)
        XCTAssertEqual(ScreenID.appointment.expectedBodySize, 60)
    }

    func test_encode_matchesExpectedSize() throws {
        let data = AppointmentData(
            startsInMinutes: 30,
            title: "Coffee at Kaffee Lade",
            location: "Basel"
        )
        let encoded = try data.encode()
        XCTAssertEqual(encoded.count, AppointmentData.encodedSize)
    }

    func test_encode_littleEndianLayout() throws {
        let data = AppointmentData(
            startsInMinutes: 0x0102,
            title: "A",
            location: "B"
        )
        let bytes = try data.encode()
        // startsInMinutes little-endian: 0x0102 -> 0x02 0x01
        XCTAssertEqual(bytes[0], 0x02)
        XCTAssertEqual(bytes[1], 0x01)
        // title[0] = 'A', title[1] = 0
        XCTAssertEqual(bytes[2], UInt8(ascii: "A"))
        XCTAssertEqual(bytes[3], 0)
        // location[0] at offset 34
        XCTAssertEqual(bytes[34], UInt8(ascii: "B"))
        // reserved at offset 58-59
        XCTAssertEqual(bytes[58], 0)
        XCTAssertEqual(bytes[59], 0)
    }

    func test_encodeDecode_roundTrip_soon() throws {
        let original = AppointmentData(
            startsInMinutes: 30,
            title: "Coffee at Kaffee Lade",
            location: "Basel"
        )
        let bytes = try original.encode()
        let decoded = try AppointmentData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_now() throws {
        let original = AppointmentData(
            startsInMinutes: 0,
            title: "Team standup",
            location: "Conference room"
        )
        let bytes = try original.encode()
        let decoded = try AppointmentData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_past() throws {
        let original = AppointmentData(
            startsInMinutes: -15,
            title: "Lunch meeting",
            location: "Marktplatz"
        )
        let bytes = try original.encode()
        let decoded = try AppointmentData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_maxLengthStrings() throws {
        let title = String(repeating: "T", count: 31)
        let location = String(repeating: "L", count: 23)
        let original = AppointmentData(
            startsInMinutes: 60,
            title: title,
            location: location
        )
        let bytes = try original.encode()
        let decoded = try AppointmentData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encode_rejectsTitleTooLong() {
        let data = AppointmentData(
            startsInMinutes: 30,
            title: String(repeating: "x", count: 32),
            location: "ok"
        )
        XCTAssertThrowsError(try data.encode()) { error in
            guard case .valueOutOfRange = error as? BLEProtocolError else {
                XCTFail("expected valueOutOfRange, got \(error)")
                return
            }
        }
    }

    func test_encode_rejectsLocationTooLong() {
        let data = AppointmentData(
            startsInMinutes: 30,
            title: "ok",
            location: String(repeating: "x", count: 24)
        )
        XCTAssertThrowsError(try data.encode())
    }

    func test_encode_rejectsMinutesOutOfRange() {
        let tooLow = AppointmentData(startsInMinutes: -1441, title: "ok", location: "ok")
        XCTAssertThrowsError(try tooLow.encode()) { error in
            XCTAssertEqual(error as? BLEProtocolError, .valueOutOfRange(field: "appointment.startsInMinutes"))
        }
        let tooHigh = AppointmentData(startsInMinutes: 10081, title: "ok", location: "ok")
        XCTAssertThrowsError(try tooHigh.encode())
    }

    func test_decode_rejectsReservedByte() throws {
        var bytes = try AppointmentData(
            startsInMinutes: 30,
            title: "ok",
            location: "ok"
        ).encode()
        bytes[58] = 0xAA
        XCTAssertThrowsError(try AppointmentData.decode(bytes)) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .nonZeroBodyReserved(field: "appointment.reserved")
            )
        }
    }

    func test_decode_rejectsMinutesOutOfRange() {
        var bytes = Data(repeating: 0, count: AppointmentData.encodedSize)
        // Write -1441 as int16 LE
        let val: Int16 = -1441
        bytes[0] = UInt8(truncatingIfNeeded: UInt16(bitPattern: val))
        bytes[1] = UInt8(truncatingIfNeeded: UInt16(bitPattern: val) >> 8)
        XCTAssertThrowsError(try AppointmentData.decode(bytes)) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "appointment.startsInMinutes")
            )
        }
    }

    func test_decode_wrongBodySize() {
        let short = Data(repeating: 0, count: 4)
        XCTAssertThrowsError(try AppointmentData.decode(short)) { error in
            guard case .bodyLengthMismatch(let screen, let expected, let actual) =
                error as? BLEProtocolError
            else {
                XCTFail("wrong error: \(error)")
                return
            }
            XCTAssertEqual(screen, .appointment)
            XCTAssertEqual(expected, 60)
            XCTAssertEqual(actual, 4)
        }
    }

    func test_screenPayloadCodec_roundTrip() throws {
        let data = AppointmentData(
            startsInMinutes: 30,
            title: "Coffee at Kaffee Lade",
            location: "Basel"
        )
        let payload = ScreenPayload.appointment(data, flags: [])
        let bytes = try ScreenPayloadCodec.encode(payload)
        XCTAssertEqual(bytes.count, 8 + AppointmentData.encodedSize)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.screenID, .appointment)
    }

    func test_screenPayloadCodec_nightMode() throws {
        let data = AppointmentData(
            startsInMinutes: -15,
            title: "Past event",
            location: "Here"
        )
        let payload = ScreenPayload.appointment(data, flags: [.nightMode])
        let bytes = try ScreenPayloadCodec.encode(payload)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.flags, [.nightMode])
    }

    func test_encodeDecode_boundaryValues() throws {
        // Minimum starts_in_minutes
        let minData = AppointmentData(startsInMinutes: -1440, title: "Min", location: "Here")
        let minBytes = try minData.encode()
        XCTAssertEqual(try AppointmentData.decode(minBytes), minData)

        // Maximum starts_in_minutes
        let maxData = AppointmentData(startsInMinutes: 10080, title: "Max", location: "There")
        let maxBytes = try maxData.encode()
        XCTAssertEqual(try AppointmentData.decode(maxBytes), maxData)
    }
}
