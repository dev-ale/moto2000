import XCTest
import BLEProtocol
@testable import ScramCore

final class ScreenPreferencesTests: XCTestCase {
    func test_roundTrip_preservesOrderAndDisabled() throws {
        let store = InMemoryKeyValueStore()
        let prefs = ScreenPreferences(
            orderedScreenIDs: [0x0D, 0x03, 0x01, 0x02],
            disabledScreenIDs: [0x02]
        )
        try prefs.save(to: store)
        let loaded = ScreenPreferences.load(from: store)
        XCTAssertEqual(loaded, prefs)
    }

    func test_load_withNoDataReturnsNil() {
        let store = InMemoryKeyValueStore()
        XCTAssertNil(ScreenPreferences.load(from: store))
    }

    func test_apply_reordersBaseList() {
        let prefs = ScreenPreferences(
            orderedScreenIDs: [0x03, 0x0D, 0x02, 0x01],
            disabledScreenIDs: []
        )
        let result = prefs.apply(to: ScreenSelection.availableScreens)
        let ids = result.map { $0.screenID.rawValue }
        // Preferred screens appear first in the requested order.
        XCTAssertEqual(Array(ids.prefix(4)), [0x03, 0x0D, 0x02, 0x01])
        // All available screens are present (preferred + appended remainder).
        XCTAssertEqual(ids.count, ScreenSelection.availableScreens.count)
        XCTAssertTrue(result.allSatisfy { $0.isEnabled })
    }

    func test_apply_marksDisabledScreens() {
        let prefs = ScreenPreferences(
            orderedScreenIDs: [0x0D, 0x03, 0x02, 0x01],
            disabledScreenIDs: [0x02]
        )
        let result = prefs.apply(to: ScreenSelection.availableScreens)
        let speed = result.first { $0.screenID == .speedHeading }
        XCTAssertEqual(speed?.isEnabled, false)
    }

    func test_apply_appendsScreensMissingFromOrder() {
        // Persisted order omits NAV; result should still include it.
        let prefs = ScreenPreferences(
            orderedScreenIDs: [0x0D, 0x03, 0x02],
            disabledScreenIDs: []
        )
        let result = prefs.apply(to: ScreenSelection.availableScreens)
        XCTAssertTrue(result.contains { $0.screenID == .navigation })
    }
}
