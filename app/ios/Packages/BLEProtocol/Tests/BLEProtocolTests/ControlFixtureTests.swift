import XCTest

@testable import BLEProtocol

/// Golden fixture tests for the `control` characteristic. Same contract as
/// the screen-data ``ValidFixtureTests`` / ``InvalidFixtureTests``: every
/// `.bin` under `protocol/fixtures/control/valid/` must round-trip through
/// the Swift codec, and every blob under `control/invalid/` must fail with
/// the documented error.
final class ControlFixtureTests: XCTestCase {
    @MainActor
    func test_validFixturesRoundTrip() throws {
        let names = try FixtureLoader.controlValidFixtureNames()
        XCTAssertFalse(names.isEmpty)
        for name in names {
            try XCTContext.runActivity(named: "control/valid/\(name)") { _ in
                let spec = try FixtureLoader.loadJSON("control/valid/\(name).json")
                let bytes = try FixtureLoader.load("control/valid/\(name).bin")

                let decoded = try ControlCommand.decode(bytes)
                let expected = try makeExpected(from: spec)
                XCTAssertEqual(decoded, expected, "decoded mismatch for \(name)")

                let reencoded = decoded.encode()
                XCTAssertEqual(reencoded, bytes, "byte mismatch for \(name)")
            }
        }
    }

    @MainActor
    func test_invalidFixturesAreRejected() throws {
        let names = try FixtureLoader.controlInvalidFixtureNames()
        XCTAssertFalse(names.isEmpty)
        for name in names {
            try XCTContext.runActivity(named: "control/invalid/\(name)") { _ in
                let spec = try FixtureLoader.loadJSON("control/invalid/\(name).json")
                guard let expectedKind = spec["expected_error"] as? String else {
                    XCTFail("\(name) missing expected_error")
                    return
                }
                let bytes = try FixtureLoader.load("control/invalid/\(name).bin")
                do {
                    let decoded = try ControlCommand.decode(bytes)
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

    private func makeExpected(from spec: [String: Any]) throws -> ControlCommand {
        guard let command = spec["command"] as? String else {
            throw FixtureError.missingField("command")
        }
        switch command {
        case "setActiveScreen":
            guard let screenName = spec["screen"] as? String else {
                throw FixtureError.missingField("screen")
            }
            guard let id = ScreenID.fromName(screenName) else {
                throw FixtureError.unsupportedScreen(screenName)
            }
            return .setActiveScreen(id)
        case "setBrightness":
            guard let brightness = spec["brightness"] as? Int else {
                throw FixtureError.missingField("brightness")
            }
            return .setBrightness(UInt8(brightness))
        case "sleep":
            return .sleep
        case "wake":
            return .wake
        case "clearAlertOverlay":
            return .clearAlertOverlay
        default:
            throw FixtureError.unsupportedScreen(command)
        }
    }
}

private extension ScreenID {
    /// Map fixture screen-name strings to enum cases without depending on
    /// auto-generated case names that don't match the JSON snake-case
    /// convention.
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
