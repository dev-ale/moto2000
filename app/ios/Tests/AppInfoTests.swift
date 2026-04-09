import XCTest
@testable import ScramScreen

final class AppInfoTests: XCTestCase {
    func test_taglineIsNotEmpty() {
        XCTAssertFalse(AppInfo.tagline.isEmpty)
    }

    func test_protocolVersionIsV1() {
        // Slice 0 ships protocol v1. When Slice 1 lands, update both the
        // constant and this test together so we notice unintentional bumps.
        XCTAssertEqual(AppInfo.protocolVersion, 0x01)
    }
}
