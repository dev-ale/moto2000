import XCTest

@testable import BLEProtocol

/// Every `.bin` under `protocol/fixtures/invalid/` must fail to decode with the
/// exact error named by its `.json` sibling's `expected_error` field.
final class InvalidFixtureTests: XCTestCase {
    @MainActor
    func test_allInvalidFixturesAreRejectedWithExpectedError() throws {
        let names = try FixtureLoader.invalidFixtureNames()
        XCTAssertFalse(names.isEmpty)
        for name in names {
            try XCTContext.runActivity(named: "fixture: \(name)") { _ in
                let spec = try FixtureLoader.loadJSON("invalid/\(name).json")
                guard let expectedName = spec["expected_error"] as? String else {
                    XCTFail("fixture \(name) missing expected_error")
                    return
                }
                let bytes = try FixtureLoader.load("invalid/\(name).bin")
                do {
                    let payload = try ScreenPayloadCodec.decode(bytes)
                    XCTFail("fixture \(name) decoded as \(payload) but should have failed with \(expectedName)")
                } catch let error as BLEProtocolError {
                    XCTAssertEqual(
                        error.kind,
                        expectedName,
                        "fixture \(name) failed with \(error.kind) but expected \(expectedName)"
                    )
                } catch {
                    XCTFail("fixture \(name) failed with non-protocol error: \(error)")
                }
            }
        }
    }
}

extension BLEProtocolError {
    /// Stable string tag used to match fixture `expected_error` values.
    var kind: String {
        switch self {
        case .truncatedHeader: return "truncatedHeader"
        case .unsupportedVersion: return "unsupportedVersion"
        case .invalidReserved: return "invalidReserved"
        case .unknownScreenId: return "unknownScreenId"
        case .truncatedBody: return "truncatedBody"
        case .bodyLengthMismatch: return "bodyLengthMismatch"
        case .reservedFlagsSet: return "reservedFlagsSet"
        case .unterminatedString: return "unterminatedString"
        case .valueOutOfRange: return "valueOutOfRange"
        case .nonZeroBodyReserved: return "nonZeroBodyReserved"
        case .unknownCommand: return "unknownCommand"
        case .invalidCommandValue: return "invalidCommandValue"
        }
    }
}
