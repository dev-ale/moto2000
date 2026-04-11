import XCTest

@testable import ScramCore

final class MaintenanceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: MaintenanceStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MaintenanceStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = MaintenanceStore(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Empty state

    func test_loadAll_returnsEmptyArrayWhenNothingSaved() {
        let result = store.loadAll()
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Save and load

    func test_save_persistsAndLoadsEntry() {
        let entry = makeEntry(type: .oilChange, odometerKm: 5000)
        store.save(entry)

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, entry.id)
        XCTAssertEqual(loaded.first?.type, .oilChange)
        XCTAssertEqual(loaded.first?.odometerKm, 5000)
    }

    func test_save_multipleEntries_allPersisted() {
        store.save(makeEntry(type: .oilChange, odometerKm: 5000))
        store.save(makeEntry(type: .chainLube, odometerKm: 5500))
        store.save(makeEntry(type: .tires, odometerKm: 10000))

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 3)
    }

    // MARK: - Ordering

    func test_loadAll_returnsSortedByDateDescending() {
        let oldest = makeEntry(
            date: Date(timeIntervalSince1970: 1000),
            type: .brakes,
            odometerKm: 1000
        )
        let newest = makeEntry(
            date: Date(timeIntervalSince1970: 3000),
            type: .oilChange,
            odometerKm: 3000
        )

        store.save(newest)
        store.save(oldest)

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].odometerKm, 3000, "Newest should be first")
        XCTAssertEqual(loaded[1].odometerKm, 1000, "Oldest should be last")
    }

    // MARK: - Delete all

    func test_deleteAll_removesAllEntries() {
        store.save(makeEntry(type: .oilChange, odometerKm: 5000))
        store.save(makeEntry(type: .chainLube, odometerKm: 5500))

        store.deleteAll()

        let loaded = store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Round-trip fidelity

    func test_roundTrip_preservesAllFields() {
        let entry = MaintenanceEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            type: .sparkPlugs,
            odometerKm: 12345.6,
            notes: "Replaced with NGK CR8E"
        )
        store.save(entry)

        let loaded = store.loadAll().first!
        XCTAssertEqual(loaded.id, entry.id)
        XCTAssertEqual(loaded.type, .sparkPlugs)
        XCTAssertEqual(loaded.odometerKm, 12345.6, accuracy: 0.001)
        XCTAssertEqual(loaded.notes, "Replaced with NGK CR8E")
    }

    // MARK: - Helpers

    private func makeEntry(
        date: Date = Date(),
        type: MaintenanceType,
        odometerKm: Double
    ) -> MaintenanceEntry {
        MaintenanceEntry(
            date: date,
            type: type,
            odometerKm: odometerKm,
            notes: ""
        )
    }
}
