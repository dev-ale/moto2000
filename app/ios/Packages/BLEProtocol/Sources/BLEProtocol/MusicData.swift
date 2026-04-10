import Foundation

/// Decoded body for a `music` screen payload.
///
/// Layout (little-endian, 86 bytes total):
/// ```
/// offset 0    : uint8  music_flags    (bit 0 = isPlaying; bits 1..7 reserved)
/// offset 1    : uint8  reserved       (must be 0)
/// offset 2..3 : uint16 positionSeconds (0xFFFF = unknown)
/// offset 4..5 : uint16 durationSeconds (0xFFFF = unknown)
/// offset 6..37 : char[32] title  (UTF-8, null-terminated, ≤31 bytes)
/// offset 38..61: char[24] artist (UTF-8, null-terminated, ≤23 bytes)
/// offset 62..85: char[24] album  (UTF-8, null-terminated, ≤23 bytes)
/// ```
///
/// Matches `ble_music_data_t` in the C codec.
public struct MusicData: Equatable, Sendable {
    public static let encodedSize: Int = 86
    public static let unknownU16: UInt16 = 0xFFFF

    public static let titleFieldLength: Int = 32
    public static let artistFieldLength: Int = 24
    public static let albumFieldLength: Int = 24

    public static let playingFlag: UInt8 = 1 << 0
    static let reservedFlagMask: UInt8 = 0b1111_1110

    /// Raw flags byte. Bit 0 = isPlaying.
    public var musicFlags: UInt8
    /// Current playback position in seconds, or `0xFFFF` for unknown.
    public var positionSeconds: UInt16
    /// Track duration in seconds, or `0xFFFF` for unknown.
    public var durationSeconds: UInt16
    /// Fixed-length UTF-8 string, ≤ 31 bytes to leave room for a terminator.
    public var title: String
    /// Fixed-length UTF-8 string, ≤ 23 bytes.
    public var artist: String
    /// Fixed-length UTF-8 string, ≤ 23 bytes.
    public var album: String

    public init(
        musicFlags: UInt8,
        positionSeconds: UInt16,
        durationSeconds: UInt16,
        title: String,
        artist: String,
        album: String
    ) {
        self.musicFlags = musicFlags
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.title = title
        self.artist = artist
        self.album = album
    }

    public var isPlaying: Bool { (musicFlags & Self.playingFlag) != 0 }

    static func decode(_ body: Data) throws -> MusicData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .music,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let flags = try reader.readUInt8()
        let reserved = try reader.readUInt8()
        guard reserved == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "music.reserved")
        }
        guard (flags & Self.reservedFlagMask) == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "music.flags")
        }
        let position = try reader.readUInt16()
        let duration = try reader.readUInt16()
        let title = try reader.readFixedString(length: Self.titleFieldLength)
        let artist = try reader.readFixedString(length: Self.artistFieldLength)
        let album = try reader.readFixedString(length: Self.albumFieldLength)
        return MusicData(
            musicFlags: flags,
            positionSeconds: position,
            durationSeconds: duration,
            title: title,
            artist: artist,
            album: album
        )
    }

    func encode() throws -> Data {
        guard (musicFlags & Self.reservedFlagMask) == 0 else {
            throw BLEProtocolError.nonZeroBodyReserved(field: "music.flags")
        }
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeUInt8(musicFlags)
        writer.writeUInt8(0)  // reserved
        writer.writeUInt16(positionSeconds)
        writer.writeUInt16(durationSeconds)
        try writer.writeFixedString(title, length: Self.titleFieldLength)
        try writer.writeFixedString(artist, length: Self.artistFieldLength)
        try writer.writeFixedString(album, length: Self.albumFieldLength)
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }
}
