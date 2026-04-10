import XCTest

@testable import BLEProtocol

/// Golden fixture tests: every `.bin` under `protocol/fixtures/valid/` must
/// decode to exactly the values in its `.json` neighbor and re-encode to
/// the same bytes.
final class ValidFixtureTests: XCTestCase {
    func test_fixtureDirectoryIsFound() throws {
        let names = try FixtureLoader.validFixtureNames()
        XCTAssertFalse(names.isEmpty, "no fixtures found under valid/")
    }

    @MainActor
    func test_allValidFixturesRoundTrip() throws {
        let names = try FixtureLoader.validFixtureNames()
        for name in names {
            try XCTContext.runActivity(named: "fixture: \(name)") { _ in
                try runRoundTrip(named: name)
            }
        }
    }

    // MARK: - per-fixture round trip

    private func runRoundTrip(named name: String) throws {
        let spec = try FixtureLoader.loadJSON("valid/\(name).json")
        let bytes = try FixtureLoader.load("valid/\(name).bin")

        let decoded = try ScreenPayloadCodec.decode(bytes)
        let expected = try makeExpected(from: spec)
        XCTAssertEqual(decoded, expected, "decoded payload differs from spec for \(name)")

        let reencoded = try ScreenPayloadCodec.encode(decoded)
        XCTAssertEqual(
            reencoded,
            bytes,
            "re-encoded bytes differ from golden blob for \(name)\nexpected: \(bytes.hex)\nactual:   \(reencoded.hex)"
        )
    }

    // MARK: - spec → ScreenPayload

    private func makeExpected(from spec: [String: Any]) throws -> ScreenPayload {
        guard let screen = spec["screen"] as? String else {
            throw FixtureError.missingField("screen")
        }
        let flagNames = (spec["flags"] as? [String]) ?? []
        let flags = try ScreenFlags(parsing: flagNames)
        guard let body = spec["body"] as? [String: Any] else {
            throw FixtureError.missingField("body")
        }
        switch screen {
        case "clock":
            return .clock(try ClockData(parsing: body), flags: flags)
        case "navigation":
            return .navigation(try NavData(parsing: body), flags: flags)
        case "speedHeading":
            return .speedHeading(try SpeedHeadingData(parsing: body), flags: flags)
        case "compass":
            return .compass(try CompassData(parsing: body), flags: flags)
        case "tripStats":
            return .tripStats(try TripStatsData(parsing: body), flags: flags)
        case "weather":
            return .weather(try WeatherData(parsing: body), flags: flags)
        case "leanAngle":
            return .leanAngle(try LeanAngleData(parsing: body), flags: flags)
        case "music":
            return .music(try MusicData(parsing: body), flags: flags)
        case "appointment":
            return .appointment(try AppointmentData(parsing: body), flags: flags)
        case "fuelEstimate":
            return .fuelEstimate(try FuelData(parsing: body), flags: flags)
        default:
            throw FixtureError.unsupportedScreen(screen)
        }
    }
}

// MARK: - Parsing helpers (test-only)

enum FixtureError: Error, CustomStringConvertible {
    case missingField(String)
    case unsupportedScreen(String)
    case unknownFlag(String)

    var description: String {
        switch self {
        case .missingField(let f): return "missing field \(f)"
        case .unsupportedScreen(let s): return "unsupported screen \(s)"
        case .unknownFlag(let f): return "unknown flag \(f)"
        }
    }
}

extension ScreenFlags {
    init(parsing names: [String]) throws {
        var value = ScreenFlags()
        for name in names {
            switch name {
            case "ALERT": value.insert(.alert)
            case "NIGHT_MODE": value.insert(.nightMode)
            case "STALE": value.insert(.stale)
            default: throw FixtureError.unknownFlag(name)
            }
        }
        self = value
    }
}

extension ClockData {
    init(parsing body: [String: Any]) throws {
        guard let unixTime = body["unix_time"] as? Int else {
            throw FixtureError.missingField("unix_time")
        }
        guard let tz = body["tz_offset_minutes"] as? Int else {
            throw FixtureError.missingField("tz_offset_minutes")
        }
        let is24h = (body["is_24h"] as? Bool) ?? true
        self.init(unixTime: Int64(unixTime), tzOffsetMinutes: Int16(tz), is24Hour: is24h)
    }
}

extension NavData {
    init(parsing body: [String: Any]) throws {
        func doubleValue(_ key: String) throws -> Double {
            if let d = body[key] as? Double { return d }
            if let i = body[key] as? Int { return Double(i) }
            throw FixtureError.missingField(key)
        }
        func intValue(_ key: String, default defaultValue: Int? = nil) throws -> Int {
            if let i = body[key] as? Int { return i }
            if let d = body[key] as? Double { return Int(d) }
            if let defaultValue { return defaultValue }
            throw FixtureError.missingField(key)
        }
        let lat = try doubleValue("lat")
        let lng = try doubleValue("lng")
        let speed = try doubleValue("speed_kmh")
        let heading = try doubleValue("heading_deg")
        let distance = try intValue("distance_to_maneuver_m", default: 0xFFFF)
        let maneuverName = (body["maneuver"] as? String) ?? "none"
        guard
            let maneuver = ManeuverType.allCases.first(where: { "\($0)" == maneuverName })
        else {
            throw FixtureError.missingField("maneuver")
        }
        let street = (body["street_name"] as? String) ?? ""
        let eta = try intValue("eta_minutes", default: 0xFFFF)
        let remainingKm: Double
        if let d = body["remaining_km"] as? Double {
            remainingKm = d
        } else if let i = body["remaining_km"] as? Int {
            remainingKm = Double(i)
        } else {
            remainingKm = -1
        }
        let remainingX10: UInt16 = remainingKm < 0 ? 0xFFFF : UInt16(Int(round(remainingKm * 10)))
        self.init(
            latitudeE7: Int32(Int(round(lat * 1e7))),
            longitudeE7: Int32(Int(round(lng * 1e7))),
            speedKmhX10: UInt16(Int(round(speed * 10))),
            headingDegX10: UInt16(Int(round(heading * 10))),
            distanceToManeuverMeters: UInt16(distance),
            maneuver: maneuver,
            streetName: street,
            etaMinutes: UInt16(eta),
            remainingKmX10: remainingX10
        )
    }
}

extension SpeedHeadingData {
    init(parsing body: [String: Any]) throws {
        func doubleValue(_ key: String) throws -> Double {
            if let d = body[key] as? Double { return d }
            if let i = body[key] as? Int { return Double(i) }
            throw FixtureError.missingField(key)
        }
        let speed = try doubleValue("speed_kmh")
        let heading = try doubleValue("heading_deg")
        let altitude = try doubleValue("altitude_m")
        let temperature = try doubleValue("temperature_celsius")
        self.init(
            speedKmhX10: UInt16(Int(round(speed * 10))),
            headingDegX10: UInt16(Int(round(heading * 10))),
            altitudeMeters: Int16(Int(round(altitude))),
            temperatureCelsiusX10: Int16(Int(round(temperature * 10)))
        )
    }
}

extension CompassData {
    init(parsing body: [String: Any]) throws {
        func doubleValue(_ key: String) throws -> Double {
            if let d = body[key] as? Double { return d }
            if let i = body[key] as? Int { return Double(i) }
            throw FixtureError.missingField(key)
        }
        let magnetic = try doubleValue("magnetic_heading_deg")
        let accuracy = try doubleValue("heading_accuracy_deg")
        let trueRaw: UInt16
        if let raw = body["true_heading_deg_raw"] as? Int {
            trueRaw = UInt16(raw)
        } else if let d = body["true_heading_deg"] as? Double {
            trueRaw = UInt16(Int(round(d * 10)))
        } else if let i = body["true_heading_deg"] as? Int {
            trueRaw = UInt16(i * 10)
        } else {
            throw FixtureError.missingField("true_heading_deg")
        }
        let useTrue = (body["use_true_heading"] as? Bool) ?? false
        let flags: UInt8 = useTrue ? CompassData.useTrueHeadingFlag : 0
        self.init(
            magneticHeadingDegX10: UInt16(Int(round(magnetic * 10))),
            trueHeadingDegX10: trueRaw,
            headingAccuracyDegX10: UInt16(Int(round(accuracy * 10))),
            flags: flags
        )
    }
}

extension TripStatsData {
    init(parsing body: [String: Any]) throws {
        func intValue(_ key: String) throws -> Int {
            if let i = body[key] as? Int { return i }
            if let d = body[key] as? Double { return Int(d) }
            throw FixtureError.missingField(key)
        }
        func doubleValue(_ key: String) throws -> Double {
            if let d = body[key] as? Double { return d }
            if let i = body[key] as? Int { return Double(i) }
            throw FixtureError.missingField(key)
        }
        let rideTime = try intValue("ride_time_seconds")
        let distance = try intValue("distance_meters")
        let avg = try doubleValue("average_speed_kmh")
        let maxKmh = try doubleValue("max_speed_kmh")
        let ascent = try intValue("ascent_meters")
        let descent = try intValue("descent_meters")
        self.init(
            rideTimeSeconds: UInt32(rideTime),
            distanceMeters: UInt32(distance),
            averageSpeedKmhX10: UInt16(Int(round(avg * 10))),
            maxSpeedKmhX10: UInt16(Int(round(maxKmh * 10))),
            ascentMeters: UInt16(ascent),
            descentMeters: UInt16(descent)
        )
    }
}

extension WeatherData {
    init(parsing body: [String: Any]) throws {
        guard let conditionName = body["condition"] as? String else {
            throw FixtureError.missingField("condition")
        }
        guard let condition = WeatherConditionWire.allCases.first(where: { "\($0)" == conditionName }) else {
            throw FixtureError.missingField("condition")
        }
        func doubleValue(_ key: String) throws -> Double {
            if let d = body[key] as? Double { return d }
            if let i = body[key] as? Int { return Double(i) }
            throw FixtureError.missingField(key)
        }
        let temp = try doubleValue("temperature_celsius")
        let high = try doubleValue("high_celsius")
        let low = try doubleValue("low_celsius")
        let name = (body["location_name"] as? String) ?? ""
        self.init(
            condition: condition,
            temperatureCelsiusX10: Int16(Int(round(temp * 10))),
            highCelsiusX10: Int16(Int(round(high * 10))),
            lowCelsiusX10: Int16(Int(round(low * 10))),
            locationName: name
        )
    }
}

extension LeanAngleData {
    init(parsing body: [String: Any]) throws {
        func doubleValue(_ key: String) throws -> Double {
            if let d = body[key] as? Double { return d }
            if let i = body[key] as? Int { return Double(i) }
            throw FixtureError.missingField(key)
        }
        func intValue(_ key: String) throws -> Int {
            if let i = body[key] as? Int { return i }
            if let d = body[key] as? Double { return Int(d) }
            throw FixtureError.missingField(key)
        }
        let current = try doubleValue("current_lean_deg")
        let maxLeft = try doubleValue("max_left_lean_deg")
        let maxRight = try doubleValue("max_right_lean_deg")
        let confidence = try intValue("confidence_percent")
        self.init(
            currentLeanDegX10: Int16(Int((current * 10).rounded())),
            maxLeftLeanDegX10: UInt16(Int((maxLeft * 10).rounded())),
            maxRightLeanDegX10: UInt16(Int((maxRight * 10).rounded())),
            confidencePercent: UInt8(confidence)
        )
    }
}

extension MusicData {
    init(parsing body: [String: Any]) throws {
        let title = (body["title"] as? String) ?? ""
        let artist = (body["artist"] as? String) ?? ""
        let album = (body["album"] as? String) ?? ""
        let isPlaying = (body["is_playing"] as? Bool) ?? false
        let position: UInt16
        if let raw = body["position_seconds_raw"] as? Int {
            position = UInt16(raw)
        } else if let i = body["position_seconds"] as? Int {
            position = UInt16(i)
        } else if let d = body["position_seconds"] as? Double {
            position = UInt16(Int(d))
        } else {
            throw FixtureError.missingField("position_seconds")
        }
        let duration: UInt16
        if let raw = body["duration_seconds_raw"] as? Int {
            duration = UInt16(raw)
        } else if let i = body["duration_seconds"] as? Int {
            duration = UInt16(i)
        } else if let d = body["duration_seconds"] as? Double {
            duration = UInt16(Int(d))
        } else {
            throw FixtureError.missingField("duration_seconds")
        }
        let flags: UInt8 = isPlaying ? MusicData.playingFlag : 0
        self.init(
            musicFlags: flags,
            positionSeconds: position,
            durationSeconds: duration,
            title: title,
            artist: artist,
            album: album
        )
    }
}

extension AppointmentData {
    init(parsing body: [String: Any]) throws {
        func intValue(_ key: String) throws -> Int {
            if let i = body[key] as? Int { return i }
            if let d = body[key] as? Double { return Int(d) }
            throw FixtureError.missingField(key)
        }
        let minutes = try intValue("starts_in_minutes")
        let title = (body["title"] as? String) ?? ""
        let location = (body["location"] as? String) ?? ""
        self.init(
            startsInMinutes: Int16(minutes),
            title: title,
            location: location
        )
    }
}

extension FuelData {
    init(parsing body: [String: Any]) throws {
        func intValue(_ key: String, default defaultValue: Int? = nil) throws -> Int {
            if let i = body[key] as? Int { return i }
            if let d = body[key] as? Double { return Int(d) }
            if let defaultValue { return defaultValue }
            throw FixtureError.missingField(key)
        }
        let pct = try intValue("tank_percent")
        let range = try intValue("estimated_range_km", default: 0xFFFF)
        let consumption = try intValue("consumption_ml_per_km", default: 0xFFFF)
        let remaining = try intValue("fuel_remaining_ml", default: 0xFFFF)
        self.init(
            tankPercent: UInt8(pct),
            estimatedRangeKm: UInt16(range),
            consumptionMlPerKm: UInt16(consumption),
            fuelRemainingMl: UInt16(remaining)
        )
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
