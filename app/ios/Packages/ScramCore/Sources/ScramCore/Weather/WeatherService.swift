import Foundation
import BLEProtocol
import RideSimulatorKit

/// Transforms ``WeatherSnapshot`` values from any ``WeatherProvider`` into
/// encoded BLE `weather` payloads and exposes them as an ``AsyncStream`` of
/// `Data` blobs ready to write to the peripheral.
///
/// Transform rules:
///  - ``WeatherCondition`` (the domain enum) is mapped to
///    ``WeatherConditionWire`` (the wire enum). The mapping is exhaustive.
///  - Temperatures are rounded to the nearest tenth of a degree and clamped
///    to the wire range `-500..=600` (= -50°C..60°C) so out-of-range
///    upstream values render at the limit instead of breaking the pipeline.
///  - The location name is truncated to 19 UTF-8 bytes so the 20-byte
///    fixed-length field always has room for the null terminator.
///    Truncation is done on a UTF-8 code-unit boundary — we walk the string
///    and accept prefixes whose UTF-8 length fits the limit, which avoids
///    slicing a multi-byte glyph in half.
///
/// The service is a one-shot pipeline: call ``start()`` once, read
/// ``encodedPayloads`` once. It does not retain the provider's stream
/// iterator across starts.
public final class WeatherService: PayloadService, @unchecked Sendable {
    public static let maxLocationNameUTF8Bytes: Int = 19

    private let provider: any WeatherProvider
    private let channel = PayloadChannel()
    public let encodedPayloads: AsyncStream<Data>
    public var payloadStream: AsyncStream<Data> { encodedPayloads }

    private var forwardingTask: Task<Void, Never>?

    public init(provider: any WeatherProvider) {
        self.provider = provider
        self.encodedPayloads = channel.makeStream()
    }

    public func start() {
        guard forwardingTask == nil else { return }
        let stream = provider.snapshots
        forwardingTask = Task { [weak self] in
            for await snapshot in stream {
                guard let self else { return }
                if let data = self.encode(snapshot) {
                    self.channel.emit(data)
                }
            }
            self?.channel.finish()
        }
    }

    public func stop() {
        forwardingTask?.cancel()
        forwardingTask = nil
        channel.finish()
    }

    // MARK: - Transform

    func encode(_ snapshot: WeatherSnapshot) -> Data? {
        let wire = Self.wireCondition(for: snapshot.condition)
        let temperature = Self.clampTemperatureX10(snapshot.temperatureCelsius)
        let high = Self.clampTemperatureX10(snapshot.highCelsius)
        let low = Self.clampTemperatureX10(snapshot.lowCelsius)
        let name = Self.truncateLocationName(snapshot.locationName)
        let precipByte: UInt8
        if let mins = snapshot.precipMinutesUntil, mins >= 0, mins < 240 {
            precipByte = UInt8(mins)
        } else {
            precipByte = weatherPrecipNone
        }
        let data = WeatherData(
            condition: wire,
            precipMinutesUntil: precipByte,
            temperatureCelsiusX10: temperature,
            highCelsiusX10: high,
            lowCelsiusX10: low,
            locationName: name
        )
        do {
            return try ScreenPayloadCodec.encode(.weather(data, flags: []))
        } catch {
            // After clamping and truncation the codec should not fail; if
            // it does (e.g. malformed UTF-8 after truncation), drop the
            // sample instead of crashing.
            return nil
        }
    }

    static func wireCondition(for condition: WeatherCondition) -> WeatherConditionWire {
        switch condition {
        case .clear:        return .clear
        case .cloudy:       return .cloudy
        case .rain:         return .rain
        case .snow:         return .snow
        case .fog:          return .fog
        case .thunderstorm: return .thunderstorm
        case .partlyCloudy: return .partlyCloudy
        case .overcast:     return .overcast
        case .drizzle:      return .drizzle
        }
    }

    static func clampTemperatureX10(_ celsius: Double) -> Int16 {
        let raw = (celsius * 10.0).rounded()
        let clamped = min(max(raw, Double(WeatherData.minTemperatureX10)), Double(WeatherData.maxTemperatureX10))
        return Int16(clamped)
    }

    static func truncateLocationName(_ name: String) -> String {
        let utf8 = Array(name.utf8)
        if utf8.count <= maxLocationNameUTF8Bytes {
            return name
        }
        // Walk the string from the end until the UTF-8 length fits.
        var result = name
        while Array(result.utf8).count > maxLocationNameUTF8Bytes {
            result = String(result.dropLast())
            if result.isEmpty {
                break
            }
        }
        return result
    }
}
