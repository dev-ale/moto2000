import XCTest

@testable import BLEProtocol

final class MusicDataTests: XCTestCase {
    func test_encodedSizeMatchesSpec() {
        XCTAssertEqual(MusicData.encodedSize, 86)
        XCTAssertEqual(ScreenID.music.expectedBodySize, 86)
    }

    func test_encode_matchesExpectedSize() throws {
        let data = MusicData(
            musicFlags: MusicData.playingFlag,
            positionSeconds: 45,
            durationSeconds: 240,
            title: "Moving On",
            artist: "The Riders",
            album: "Asphalt"
        )
        let encoded = try data.encode()
        XCTAssertEqual(encoded.count, MusicData.encodedSize)
    }

    func test_encode_littleEndianLayout() throws {
        let data = MusicData(
            musicFlags: MusicData.playingFlag,
            positionSeconds: 0x0102,
            durationSeconds: 0x0304,
            title: "A",
            artist: "B",
            album: "C"
        )
        let bytes = try data.encode()
        // flags byte
        XCTAssertEqual(bytes[0], MusicData.playingFlag)
        // reserved
        XCTAssertEqual(bytes[1], 0)
        // position little-endian 0x0102 -> 0x02 0x01
        XCTAssertEqual(bytes[2], 0x02)
        XCTAssertEqual(bytes[3], 0x01)
        // duration 0x0304 -> 0x04 0x03
        XCTAssertEqual(bytes[4], 0x04)
        XCTAssertEqual(bytes[5], 0x03)
        // title[0] = 'A', title[1] = 0
        XCTAssertEqual(bytes[6], UInt8(ascii: "A"))
        XCTAssertEqual(bytes[7], 0)
        // artist[0] at offset 38
        XCTAssertEqual(bytes[38], UInt8(ascii: "B"))
        // album[0] at offset 62
        XCTAssertEqual(bytes[62], UInt8(ascii: "C"))
    }

    func test_encodeDecode_roundTrip_playing() throws {
        let original = MusicData(
            musicFlags: MusicData.playingFlag,
            positionSeconds: 45,
            durationSeconds: 240,
            title: "Moving On",
            artist: "The Riders",
            album: "Asphalt"
        )
        let bytes = try original.encode()
        let decoded = try MusicData.decode(bytes)
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.isPlaying)
    }

    func test_encodeDecode_roundTrip_paused() throws {
        let original = MusicData(
            musicFlags: 0,
            positionSeconds: 120,
            durationSeconds: 180,
            title: "Midnight Sun",
            artist: "Solo Project",
            album: "Demo"
        )
        let bytes = try original.encode()
        let decoded = try MusicData.decode(bytes)
        XCTAssertEqual(decoded, original)
        XCTAssertFalse(decoded.isPlaying)
    }

    func test_encodeDecode_unknownSentinels() throws {
        let original = MusicData(
            musicFlags: MusicData.playingFlag,
            positionSeconds: MusicData.unknownU16,
            durationSeconds: MusicData.unknownU16,
            title: "Radio Stream",
            artist: "Live DJ",
            album: "Broadcast"
        )
        let bytes = try original.encode()
        let decoded = try MusicData.decode(bytes)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.positionSeconds, 0xFFFF)
        XCTAssertEqual(decoded.durationSeconds, 0xFFFF)
    }

    func test_encodeDecode_maxLengthStrings() throws {
        // 31-byte title (leaves room for terminator), 23-byte artist/album.
        let title = String(repeating: "T", count: 31)
        let artist = String(repeating: "A", count: 23)
        let album = String(repeating: "B", count: 23)
        let original = MusicData(
            musicFlags: MusicData.playingFlag,
            positionSeconds: 0,
            durationSeconds: 0,
            title: title,
            artist: artist,
            album: album
        )
        let bytes = try original.encode()
        let decoded = try MusicData.decode(bytes)
        XCTAssertEqual(decoded, original)
    }

    func test_encode_rejectsTitleTooLong() {
        let data = MusicData(
            musicFlags: 0,
            positionSeconds: 0,
            durationSeconds: 0,
            title: String(repeating: "x", count: 32),  // 32 = no room for terminator
            artist: "ok",
            album: "ok"
        )
        XCTAssertThrowsError(try data.encode()) { error in
            guard case .valueOutOfRange = error as? BLEProtocolError else {
                XCTFail("expected valueOutOfRange, got \(error)")
                return
            }
        }
    }

    func test_encode_rejectsArtistTooLong() {
        let data = MusicData(
            musicFlags: 0,
            positionSeconds: 0,
            durationSeconds: 0,
            title: "ok",
            artist: String(repeating: "x", count: 24),
            album: "ok"
        )
        XCTAssertThrowsError(try data.encode())
    }

    func test_encode_rejectsAlbumTooLong() {
        let data = MusicData(
            musicFlags: 0,
            positionSeconds: 0,
            durationSeconds: 0,
            title: "ok",
            artist: "ok",
            album: String(repeating: "x", count: 24)
        )
        XCTAssertThrowsError(try data.encode())
    }

    func test_encode_rejectsReservedFlagBits() {
        let data = MusicData(
            musicFlags: 0b0000_0010,
            positionSeconds: 0,
            durationSeconds: 0,
            title: "ok",
            artist: "ok",
            album: "ok"
        )
        XCTAssertThrowsError(try data.encode()) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .nonZeroBodyReserved(field: "music.flags")
            )
        }
    }

    func test_decode_rejectsReservedByte() throws {
        var bytes = try MusicData(
            musicFlags: 0,
            positionSeconds: 0,
            durationSeconds: 0,
            title: "ok",
            artist: "ok",
            album: "ok"
        ).encode()
        bytes[1] = 0xAA
        XCTAssertThrowsError(try MusicData.decode(bytes)) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .nonZeroBodyReserved(field: "music.reserved")
            )
        }
    }

    func test_decode_rejectsReservedFlagBits() throws {
        var bytes = try MusicData(
            musicFlags: 0,
            positionSeconds: 0,
            durationSeconds: 0,
            title: "ok",
            artist: "ok",
            album: "ok"
        ).encode()
        bytes[0] = 0b1000_0000
        XCTAssertThrowsError(try MusicData.decode(bytes)) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .nonZeroBodyReserved(field: "music.flags")
            )
        }
    }

    func test_decode_rejectsUnterminatedTitle() {
        // Build a valid body then splat the title field with 32 non-zero bytes.
        var bytes = Data(repeating: 0, count: MusicData.encodedSize)
        bytes[0] = MusicData.playingFlag
        for i in 0..<32 {
            bytes[6 + i] = 0x41  // 'A'
        }
        XCTAssertThrowsError(try MusicData.decode(bytes)) { error in
            XCTAssertEqual(
                error as? BLEProtocolError,
                .unterminatedString
            )
        }
    }

    func test_decode_wrongBodySize() {
        let short = Data(repeating: 0, count: 4)
        XCTAssertThrowsError(try MusicData.decode(short)) { error in
            guard case .bodyLengthMismatch(let screen, let expected, let actual) =
                error as? BLEProtocolError
            else {
                XCTFail("wrong error: \(error)")
                return
            }
            XCTAssertEqual(screen, .music)
            XCTAssertEqual(expected, 86)
            XCTAssertEqual(actual, 4)
        }
    }

    func test_screenPayloadCodec_roundTrip() throws {
        let data = MusicData(
            musicFlags: MusicData.playingFlag,
            positionSeconds: 45,
            durationSeconds: 240,
            title: "Moving On",
            artist: "The Riders",
            album: "Asphalt"
        )
        let payload = ScreenPayload.music(data, flags: [])
        let bytes = try ScreenPayloadCodec.encode(payload)
        XCTAssertEqual(bytes.count, 8 + MusicData.encodedSize)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.screenID, .music)
    }

    func test_screenPayloadCodec_nightMode() throws {
        let data = MusicData(
            musicFlags: 0,
            positionSeconds: 120,
            durationSeconds: 180,
            title: "Midnight Sun",
            artist: "Solo Project",
            album: "Demo"
        )
        let payload = ScreenPayload.music(data, flags: [.nightMode])
        let bytes = try ScreenPayloadCodec.encode(payload)
        let decoded = try ScreenPayloadCodec.decode(bytes)
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.flags, [.nightMode])
    }
}
