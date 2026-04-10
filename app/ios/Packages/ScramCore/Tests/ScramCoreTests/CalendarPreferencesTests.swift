import XCTest
@testable import ScramCore

final class CalendarPreferencesTests: XCTestCase {

    // MARK: - Default state

    func test_newPreferences_allCalendarsEnabledByDefault() {
        let store = InMemoryKeyValueStore()
        let prefs = CalendarPreferences(store: store)

        XCTAssertTrue(prefs.isSelected("calendar-1"))
        XCTAssertTrue(prefs.isSelected("calendar-2"))
        XCTAssertTrue(prefs.disabledCalendarIDs.isEmpty)
    }

    // MARK: - Toggle

    func test_toggle_disablesEnabledCalendar() {
        let store = InMemoryKeyValueStore()
        let prefs = CalendarPreferences(store: store)

        prefs.toggleSelection("cal-A")

        XCTAssertFalse(prefs.isSelected("cal-A"))
        XCTAssertTrue(prefs.disabledCalendarIDs.contains("cal-A"))
    }

    func test_toggle_reEnablesDisabledCalendar() {
        let store = InMemoryKeyValueStore()
        let prefs = CalendarPreferences(store: store)

        prefs.toggleSelection("cal-A")
        prefs.toggleSelection("cal-A")

        XCTAssertTrue(prefs.isSelected("cal-A"))
        XCTAssertFalse(prefs.disabledCalendarIDs.contains("cal-A"))
    }

    // MARK: - setSelected

    func test_setSelected_explicitlyDisables() {
        let store = InMemoryKeyValueStore()
        let prefs = CalendarPreferences(store: store)

        prefs.setSelected("cal-B", enabled: false)

        XCTAssertFalse(prefs.isSelected("cal-B"))
    }

    func test_setSelected_explicitlyEnables() {
        let store = InMemoryKeyValueStore()
        let prefs = CalendarPreferences(store: store)

        prefs.setSelected("cal-B", enabled: false)
        prefs.setSelected("cal-B", enabled: true)

        XCTAssertTrue(prefs.isSelected("cal-B"))
    }

    // MARK: - Persistence round-trip

    func test_roundTrip_persistsDisabledCalendars() {
        let store = InMemoryKeyValueStore()

        let prefs1 = CalendarPreferences(store: store)
        prefs1.setSelected("cal-X", enabled: false)
        prefs1.setSelected("cal-Y", enabled: false)

        // Create a new instance reading from the same store.
        let prefs2 = CalendarPreferences(store: store)

        XCTAssertFalse(prefs2.isSelected("cal-X"))
        XCTAssertFalse(prefs2.isSelected("cal-Y"))
        XCTAssertTrue(prefs2.isSelected("cal-Z"))
    }

    func test_load_withNoDataReturnsAllEnabled() {
        let store = InMemoryKeyValueStore()
        let prefs = CalendarPreferences(store: store)

        XCTAssertTrue(prefs.disabledCalendarIDs.isEmpty)
    }

    // MARK: - Reconcile

    func test_reconcile_removesStaleCalendars() {
        let store = InMemoryKeyValueStore()
        let prefs = CalendarPreferences(store: store)

        prefs.setSelected("cal-A", enabled: false)
        prefs.setSelected("cal-B", enabled: false)
        prefs.setSelected("cal-C", enabled: false)

        // cal-B was removed from the system.
        prefs.reconcile(knownCalendarIDs: ["cal-A", "cal-C"])

        XCTAssertFalse(prefs.isSelected("cal-A"))
        XCTAssertTrue(prefs.isSelected("cal-B")) // cleaned up → default enabled
        XCTAssertFalse(prefs.isSelected("cal-C"))
    }

    func test_reconcile_persistsCleanup() {
        let store = InMemoryKeyValueStore()
        let prefs = CalendarPreferences(store: store)

        prefs.setSelected("gone-cal", enabled: false)
        prefs.reconcile(knownCalendarIDs: ["existing-cal"])

        // Reload from store.
        let prefs2 = CalendarPreferences(store: store)
        XCTAssertTrue(prefs2.isSelected("gone-cal"))
    }

    func test_reconcile_newCalendarsDefaultToEnabled() {
        let store = InMemoryKeyValueStore()
        let prefs = CalendarPreferences(store: store)

        // A brand-new calendar appears that was never persisted.
        prefs.reconcile(knownCalendarIDs: ["new-cal", "another-new"])

        XCTAssertTrue(prefs.isSelected("new-cal"))
        XCTAssertTrue(prefs.isSelected("another-new"))
    }

    // MARK: - Multiple calendars

    func test_multipleCalendars_independentToggling() {
        let store = InMemoryKeyValueStore()
        let prefs = CalendarPreferences(store: store)

        prefs.setSelected("work", enabled: false)
        prefs.setSelected("personal", enabled: true)
        prefs.setSelected("holidays", enabled: false)

        XCTAssertFalse(prefs.isSelected("work"))
        XCTAssertTrue(prefs.isSelected("personal"))
        XCTAssertFalse(prefs.isSelected("holidays"))
        XCTAssertEqual(prefs.disabledCalendarIDs, ["work", "holidays"])
    }
}
