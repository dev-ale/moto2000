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

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
