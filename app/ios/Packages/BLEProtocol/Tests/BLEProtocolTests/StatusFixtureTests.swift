import XCTest

@testable import BLEProtocol

/// Golden fixture tests for the `status` characteristic. Same contract as
/// the control fixture tests: every `.bin` under `protocol/fixtures/status/valid/`
/// must round-trip through the Swift codec, and every blob under
/// `status/invalid/` must fail with the documented error.
final class StatusFixtureTests: XCTestCase {
    @MainActor
    func test_validFixturesRoundTrip() throws {
        let names = try FixtureLoader.statusValidFixtureNames()
        XCTAssertFalse(names.isEmpty)
        for name in names {
            try XCTContext.runActivity(named: "status/valid/\(name)") { _ in
                let spec = try FixtureLoader.loadJSON("status/valid/\(name).json")
                let bytes = try FixtureLoader.load("status/valid/\(name).bin")

                let decoded = try StatusMessage.decode(bytes)
                let expected = try makeExpected(from: spec)
                XCTAssertEqual(decoded, expected, "decoded mismatch for \(name)")

                let reencoded = decoded.encode()
                XCTAssertEqual(reencoded, bytes, "byte mismatch for \(name)")
            }
        }
    }

    @MainActor
    func test_invalidFixturesAreRejected() throws {
        let names = try FixtureLoader.statusInvalidFixtureNames()
        XCTAssertFalse(names.isEmpty)
        for name in names {
            try XCTContext.runActivity(named: "status/invalid/\(name)") { _ in
                let spec = try FixtureLoader.loadJSON("status/invalid/\(name).json")
                guard let expectedKind = spec["expected_error"] as? String else {
                    XCTFail("\(name) missing expected_error")
                    return
                }
                let bytes = try FixtureLoader.load("status/invalid/\(name).bin")
                do {
                    let decoded = try StatusMessage.decode(bytes)
                    XCTFail("\(name) decoded as \(decoded) instead of failing with \(expectedKind)")
                } catch let error as BLEProtocolError {
                    XCTAssertEqual(
                        error.kind,
                        expectedKind,
                        "\(name) failed with \(error.kind), expected \(expectedKind)"
                    )
                } catch {
                    XCTFail("\(name) failed with non-protocol error: \(error)")
                }
            }
        }
    }

    private func makeExpected(from spec: [String: Any]) throws -> StatusMessage {
        guard let type = spec["type"] as? String else {
            throw FixtureError.missingField("type")
        }
        switch type {
        case "screenChanged":
            guard let screenName = spec["screen"] as? String else {
                throw FixtureError.missingField("screen")
            }
            guard let id = ScreenID.fromName(screenName) else {
                throw FixtureError.unsupportedScreen(screenName)
            }
            return .screenChanged(id)
        default:
            throw FixtureError.unsupportedScreen(type)
        }
    }
}

private extension ScreenID {
    static func fromName(_ name: String) -> ScreenID? {
        switch name {
        case "navigation":   return .navigation
        case "speedHeading": return .speedHeading
        case "compass":      return .compass
        case "weather":      return .weather
        case "tripStats":    return .tripStats
        case "music":        return .music
        case "leanAngle":    return .leanAngle
        case "blitzer":      return .blitzer
        case "incomingCall": return .incomingCall
        case "fuelEstimate": return .fuelEstimate
        case "altitude":     return .altitude
        case "appointment":  return .appointment
        case "clock":        return .clock
        default:             return nil
        }
    }
}
