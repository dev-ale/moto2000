import Foundation

/// Weather condition as it appears on the wire.
///
/// The Swift domain model uses ``RideSimulatorKit/WeatherCondition`` which is
/// a `String` enum; this enum owns the stable `UInt8` wire representation and
/// is intentionally kept separate so the two can evolve independently.
public enum WeatherConditionWire: UInt8, Sendable, CaseIterable, Equatable {
    case clear        = 0x00
    case cloudy       = 0x01
    case rain         = 0x02
    case snow         = 0x03
    case fog          = 0x04
    case thunderstorm = 0x05
    case partlyCloudy = 0x06
    case overcast     = 0x07
    case drizzle      = 0x08
}

/// Sentinel for "no precipitation in the forecast horizon" carried in
/// ``WeatherData/precipMinutesUntil``.
public let weatherPrecipNone: UInt8 = 0xFF

/// Decoded body for a `weather` screen payload.
///
/// Layout (little-endian, 28 bytes total):
/// ```
/// offset 0     : uint8  condition          (see WeatherConditionWire)
/// offset 1     : uint8  reserved           (must be 0)
/// offset 2..3  : int16  temperature_x10    range -500..=600
/// offset 4..5  : int16  high_x10           range -500..=600
/// offset 6..7  : int16  low_x10            range -500..=600
/// offset 8..27 : char[20] location_name    UTF-8, null-terminated,
///                                          must fit a terminator (len < 20)
/// ```
///
/// Matches `ble_weather_data_t` in the C codec.
public struct WeatherData: Equatable, Sendable {
    public static let encodedSize: Int = 28
    public static let locationNameFieldLength: Int = 20

    /// Temperatures are stored as signed tenths of a degree Celsius.
    /// Valid range: `-500..=600` (i.e. -50.0°C .. 60.0°C).
    public static let minTemperatureX10: Int16 = -500
    public static let maxTemperatureX10: Int16 = 600

    public var condition: WeatherConditionWire
    /// 0..240 minutes until the next precipitation, or
    /// `weatherPrecipNone` when nothing is expected.
    public var precipMinutesUntil: UInt8
    public var temperatureCelsiusX10: Int16
    public var highCelsiusX10: Int16
    public var lowCelsiusX10: Int16
    /// UTF-8 string, must be ≤ 19 bytes to leave room for a null terminator.
    public var locationName: String

    public init(
        condition: WeatherConditionWire,
        precipMinutesUntil: UInt8 = weatherPrecipNone,
        temperatureCelsiusX10: Int16,
        highCelsiusX10: Int16,
        lowCelsiusX10: Int16,
        locationName: String
    ) {
        self.condition = condition
        self.precipMinutesUntil = precipMinutesUntil
        self.temperatureCelsiusX10 = temperatureCelsiusX10
        self.highCelsiusX10 = highCelsiusX10
        self.lowCelsiusX10 = lowCelsiusX10
        self.locationName = locationName
    }

    static func decode(_ body: Data) throws -> WeatherData {
        guard body.count == Self.encodedSize else {
            throw BLEProtocolError.bodyLengthMismatch(
                screen: .weather,
                expected: Self.encodedSize,
                actual: body.count
            )
        }
        var reader = ByteReader(body)
        let conditionRaw = try reader.readUInt8()
        let precip = try reader.readUInt8()
        guard let condition = WeatherConditionWire(rawValue: conditionRaw) else {
            throw BLEProtocolError.valueOutOfRange(field: "weather.condition")
        }
        let temp = try reader.readInt16()
        let high = try reader.readInt16()
        let low = try reader.readInt16()
        let name = try reader.readFixedString(length: Self.locationNameFieldLength)

        try Self.validateTemperature(temp, field: "weather.temperatureCelsiusX10")
        try Self.validateTemperature(high, field: "weather.highCelsiusX10")
        try Self.validateTemperature(low, field: "weather.lowCelsiusX10")

        return WeatherData(
            condition: condition,
            precipMinutesUntil: precip,
            temperatureCelsiusX10: temp,
            highCelsiusX10: high,
            lowCelsiusX10: low,
            locationName: name
        )
    }

    func encode() throws -> Data {
        try Self.validateTemperature(temperatureCelsiusX10, field: "weather.temperatureCelsiusX10")
        try Self.validateTemperature(highCelsiusX10, field: "weather.highCelsiusX10")
        try Self.validateTemperature(lowCelsiusX10, field: "weather.lowCelsiusX10")
        var writer = ByteWriter(capacity: Self.encodedSize)
        writer.writeUInt8(condition.rawValue)
        writer.writeUInt8(precipMinutesUntil)
        writer.writeInt16(temperatureCelsiusX10)
        writer.writeInt16(highCelsiusX10)
        writer.writeInt16(lowCelsiusX10)
        try writer.writeFixedString(locationName, length: Self.locationNameFieldLength)
        assert(writer.data.count == Self.encodedSize)
        return writer.data
    }

    private static func validateTemperature(_ value: Int16, field: String) throws {
        guard value >= minTemperatureX10 && value <= maxTemperatureX10 else {
            throw BLEProtocolError.valueOutOfRange(field: field)
        }
    }
}
