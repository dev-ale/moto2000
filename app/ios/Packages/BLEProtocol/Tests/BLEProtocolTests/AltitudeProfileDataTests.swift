import XCTest

@testable import BLEProtocol

final class AltitudeProfileDataTests: XCTestCase {
    func test_encode_matchesExpectedSize() throws {
        let data = AltitudeProfileData(
            currentAltitudeM: 260,
            totalAscentM: 0,
            totalDescentM: 0,
            sampleCount: 1,
            profile: [260] + Array(repeating: 0, count: 59)
        )
        let encoded = try data.encode()
        XCTAssertEqual(encoded.count, AltitudeProfileData.encodedSize)
        XCTAssertEqual(encoded.count, 128)
    }

    func test_encodeDecode_roundTrip_flat() throws {
        var profile = [Int16](repeating: 260, count: 20)
        profile += [Int16](repeating: 0, count: 40)
        let original = AltitudeProfileData(
            currentAltitudeM: 260,
            totalAscentM: 0,
            totalDescentM: 0,
            sampleCount: 20,
            profile: profile
        )
        let bytes = try original.encode()
        let decoded = try AltitudeProfileData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_mountainPass() throws {
        let profileValues: [Int16] = [
            500, 532, 565, 597, 630, 662, 695, 727, 760, 792,
            825, 857, 890, 922, 955, 987, 1020, 1052, 1085, 1117,
            1150, 1182, 1215, 1247, 1280, 1312, 1345, 1377, 1410, 1442,
            1475, 1507, 1540, 1572, 1605, 1637, 1670, 1702, 1735, 1767,
            1800, 1832, 1865, 1897, 1930, 1962, 2000, 2050, 2100, 2150,
            2200, 2250, 2300, 2350, 2400, 2280, 2160, 2040, 1920, 1800,
        ]
        let original = AltitudeProfileData(
            currentAltitudeM: 1800,
            totalAscentM: 1900,
            totalDescentM: 600,
            sampleCount: 60,
            profile: profileValues
        )
        let bytes = try original.encode()
        let decoded = try AltitudeProfileData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encodeDecode_roundTrip_singleSample() throws {
        var profile = [Int16](repeating: 0, count: 60)
        profile[0] = 450
        let original = AltitudeProfileData(
            currentAltitudeM: 450,
            totalAscentM: 0,
            totalDescentM: 0,
            sampleCount: 1,
            profile: profile
        )
        let bytes = try original.encode()
        let decoded = try AltitudeProfileData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encode_rejectsSampleCountOver60() {
        let data = AltitudeProfileData(
            currentAltitudeM: 0,
            totalAscentM: 0,
            totalDescentM: 0,
            sampleCount: 61,
            profile: Array(repeating: 0, count: 60)
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "altitude.sample_count")
            )
        }
    }

    func test_decode_rejectsSampleCountOver60() {
        var bytes = [UInt8](repeating: 0, count: AltitudeProfileData.encodedSize)
        bytes[6] = 61  // sample_count
        XCTAssertThrowsError(try AltitudeProfileData.decode(Data(bytes))) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "altitude.sample_count")
            )
        }
    }

    func test_decode_rejectsNonZeroReserved() {
        var bytes = [UInt8](repeating: 0, count: AltitudeProfileData.encodedSize)
        bytes[7] = 1  // non-zero reserved
        XCTAssertThrowsError(try AltitudeProfileData.decode(Data(bytes))) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .nonZeroBodyReserved(field: "altitude.reserved")
            )
        }
    }

    func test_decode_rejectsWrongBodySize() {
        let tooShort = Data(repeating: 0, count: AltitudeProfileData.encodedSize - 1)
        XCTAssertThrowsError(try AltitudeProfileData.decode(tooShort)) { error in
            guard case let .bodyLengthMismatch(screen, expected, actual) = (error as? BLEProtocolError) else {
                XCTFail("expected bodyLengthMismatch, got \(error)")
                return
            }
            XCTAssertEqual(screen, .altitude)
            XCTAssertEqual(expected, AltitudeProfileData.encodedSize)
            XCTAssertEqual(actual, AltitudeProfileData.encodedSize - 1)
        }
    }

    func test_encode_rejectsAltitudeOutOfRange() {
        let tooLow = AltitudeProfileData(
            currentAltitudeM: -501,
            totalAscentM: 0,
            totalDescentM: 0,
            sampleCount: 0,
            profile: Array(repeating: 0, count: 60)
        )
        XCTAssertThrowsError(try tooLow.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "altitude.current_altitude_m")
            )
        }

        let tooHigh = AltitudeProfileData(
            currentAltitudeM: 9001,
            totalAscentM: 0,
            totalDescentM: 0,
            sampleCount: 0,
            profile: Array(repeating: 0, count: 60)
        )
        XCTAssertThrowsError(try tooHigh.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .valueOutOfRange(field: "altitude.current_altitude_m")
            )
        }
    }

    func test_screenPayloadCodec_roundTripsAltitude() throws {
        var profile = [Int16](repeating: 260, count: 20)
        profile += [Int16](repeating: 0, count: 40)
        let original = ScreenPayload.altitude(
            AltitudeProfileData(
                currentAltitudeM: 260,
                totalAscentM: 100,
                totalDescentM: 50,
                sampleCount: 20,
                profile: profile
            ),
            flags: [.nightMode]
        )
        let encoded = try ScreenPayloadCodec.encode(original)
        // header (8) + body (128)
        XCTAssertEqual(encoded.count, 8 + AltitudeProfileData.encodedSize)
        let decoded = try ScreenPayloadCodec.decode(encoded)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.screenID, .altitude)
    }

    func test_encode_padsShortProfile() throws {
        // Provide only 5 profile entries, rest should be zero-padded
        let data = AltitudeProfileData(
            currentAltitudeM: 100,
            totalAscentM: 0,
            totalDescentM: 0,
            sampleCount: 5,
            profile: [100, 200, 300, 400, 500]
        )
        let encoded = try data.encode()
        XCTAssertEqual(encoded.count, AltitudeProfileData.encodedSize)
        let decoded = try AltitudeProfileData.decode(encoded)
        XCTAssertEqual(decoded.sampleCount, 5)
        XCTAssertEqual(decoded.profile[0], 100)
        XCTAssertEqual(decoded.profile[4], 500)
        // Padded entries should be 0
        for i in 5..<60 {
            XCTAssertEqual(decoded.profile[i], 0)
        }
    }

    func test_negativeAltitude() throws {
        var profile = [Int16](repeating: 0, count: 60)
        profile[0] = -50
        let data = AltitudeProfileData(
            currentAltitudeM: -50,
            totalAscentM: 0,
            totalDescentM: 0,
            sampleCount: 1,
            profile: profile
        )
        let encoded = try data.encode()
        let decoded = try AltitudeProfileData.decode(encoded)
        XCTAssertEqual(decoded.currentAltitudeM, -50)
        XCTAssertEqual(decoded.profile[0], -50)
    }
}
