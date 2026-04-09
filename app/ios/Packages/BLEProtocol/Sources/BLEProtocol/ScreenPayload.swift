import Foundation

/// A fully decoded screen payload: header + screen-specific body.
public enum ScreenPayload: Equatable, Sendable {
    case clock(ClockData, flags: ScreenFlags)
    case navigation(NavData, flags: ScreenFlags)
    case speedHeading(SpeedHeadingData, flags: ScreenFlags)
    case compass(CompassData, flags: ScreenFlags)
    case tripStats(TripStatsData, flags: ScreenFlags)
    case weather(WeatherData, flags: ScreenFlags)
    case leanAngle(LeanAngleData, flags: ScreenFlags)
    case music(MusicData, flags: ScreenFlags)

    public var screenID: ScreenID {
        switch self {
        case .clock: return .clock
        case .navigation: return .navigation
        case .speedHeading: return .speedHeading
        case .compass: return .compass
        case .tripStats: return .tripStats
        case .weather: return .weather
        case .leanAngle: return .leanAngle
        case .music: return .music
        }
    }

    public var flags: ScreenFlags {
        switch self {
        case .clock(_, let flags),
             .navigation(_, let flags),
             .speedHeading(_, let flags),
             .compass(_, let flags),
             .tripStats(_, let flags),
             .weather(_, let flags),
             .leanAngle(_, let flags),
             .music(_, let flags):
            return flags
        }
    }
}

/// Top-level encoder/decoder for `screen_data` characteristic writes.
public enum ScreenPayloadCodec {
    /// Decode a complete `screen_data` write.
    public static func decode(_ data: Data) throws -> ScreenPayload {
        guard data.count >= BLEProtocolConstants.headerSize else {
            throw BLEProtocolError.truncatedHeader
        }
        var reader = ByteReader(data)
        let version = try reader.readUInt8()
        guard version == BLEProtocolConstants.protocolVersion else {
            throw BLEProtocolError.unsupportedVersion(version)
        }
        let screenRaw = try reader.readUInt8()
        let flagsRaw = try reader.readUInt8()
        let reserved = try reader.readUInt8()
        guard reserved == 0 else {
            throw BLEProtocolError.invalidReserved
        }
        guard (flagsRaw & ScreenFlags.reservedMask) == 0 else {
            throw BLEProtocolError.reservedFlagsSet
        }
        let dataLength = Int(try reader.readUInt16())
        // Two reserved bytes pad the header to 8 bytes.
        let trailingReserved = try reader.readUInt16()
        guard trailingReserved == 0 else {
            throw BLEProtocolError.invalidReserved
        }
        guard let screen = ScreenID(rawValue: screenRaw) else {
            throw BLEProtocolError.unknownScreenId(screenRaw)
        }
        // Validate the declared body length against the screen's expected size
        // *before* checking against the buffer, so fixtures that declare the
        // wrong length get a specific `bodyLengthMismatch` instead of the
        // generic `truncatedBody`.
        if let expected = screen.expectedBodySize, dataLength != expected {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: screen,
                expected: expected,
                actual: dataLength
            )
        }
        guard reader.remaining >= dataLength else {
            throw BLEProtocolError.truncatedBody(
                declared: dataLength,
                available: reader.remaining
            )
        }
        let body = try reader.readBytes(dataLength)
        let flags = ScreenFlags(rawValue: flagsRaw)

        switch screen {
        case .clock:
            return .clock(try ClockData.decode(body), flags: flags)
        case .navigation:
            return .navigation(try NavData.decode(body), flags: flags)
        case .speedHeading:
            return .speedHeading(try SpeedHeadingData.decode(body), flags: flags)
        case .compass:
            return .compass(try CompassData.decode(body), flags: flags)
        case .tripStats:
            return .tripStats(try TripStatsData.decode(body), flags: flags)
        case .weather:
            return .weather(try WeatherData.decode(body), flags: flags)
        case .leanAngle:
            return .leanAngle(try LeanAngleData.decode(body), flags: flags)
        case .music:
            return .music(try MusicData.decode(body), flags: flags)
        default:
            // The other screens are reserved by Slice 1 but their bodies
            // land with their owning slices. Decoding one today is a bug.
            throw BLEProtocolError.unknownScreenId(screenRaw)
        }
    }

    /// Encode a payload into a `screen_data` write buffer.
    public static func encode(_ payload: ScreenPayload) throws -> Data {
        let body: Data
        switch payload {
        case .clock(let clock, _):
            body = try clock.encode()
        case .navigation(let nav, _):
            body = try nav.encode()
        case .speedHeading(let sh, _):
            body = try sh.encode()
        case .compass(let compass, _):
            body = try compass.encode()
        case .tripStats(let stats, _):
            body = try stats.encode()
        case .weather(let weather, _):
            body = try weather.encode()
        case .leanAngle(let lean, _):
            body = try lean.encode()
        case .music(let music, _):
            body = try music.encode()
        }
        guard body.count <= Int(UInt16.max) else {
            throw BLEProtocolError.valueOutOfRange(field: "body.count")
        }
        var writer = ByteWriter(capacity: BLEProtocolConstants.headerSize + body.count)
        writer.writeUInt8(BLEProtocolConstants.protocolVersion)
        writer.writeUInt8(payload.screenID.rawValue)
        writer.writeUInt8(payload.flags.rawValue)
        writer.writeUInt8(0)
        writer.writeUInt16(UInt16(body.count))
        writer.writeUInt16(0)  // trailing reserved
        writer.writeBytes(body)
        return writer.data
    }
}
