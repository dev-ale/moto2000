import BLEProtocol
import XCTest

@testable import ScramScreen

final class AppInfoTests: XCTestCase {
    func test_taglineIsNotEmpty() {
        XCTAssertFalse(AppInfo.tagline.isEmpty)
    }

    func test_protocolVersionMatchesBLEProtocolPackage() {
        // If the wire format is bumped, this test fails by design so we
        // notice the app and the codec have drifted out of sync.
        XCTAssertEqual(AppInfo.protocolVersion, BLEProtocolConstants.protocolVersion)
        XCTAssertEqual(AppInfo.protocolVersion, 0x01)
    }
}
