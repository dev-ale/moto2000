import XCTest

@testable import ScramCore

final class TripHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: TripHistoryStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TripHistoryStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = TripHistoryStore(defaults: defaults)
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

    func test_save_persistsAndLoadsTrip() {
        let trip = makeSummary(distanceKm: 100)
        store.save(trip)

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, trip.id)
        XCTAssertEqual(loaded.first?.distanceKm, 100)
    }

    func test_save_multipleTrips_allPersisted() {
        store.save(makeSummary(distanceKm: 50))
        store.save(makeSummary(distanceKm: 75))
        store.save(makeSummary(distanceKm: 120))

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 3)
    }

    // MARK: - Ordering

    func test_loadAll_returnsSortedByDateDescending() {
        let oldest = makeSummary(
            date: Date(timeIntervalSince1970: 1000),
            distanceKm: 10
        )
        let middle = makeSummary(
            date: Date(timeIntervalSince1970: 2000),
            distanceKm: 20
        )
        let newest = makeSummary(
            date: Date(timeIntervalSince1970: 3000),
            distanceKm: 30
        )

        // Save in scrambled order
        store.save(middle)
        store.save(oldest)
        store.save(newest)

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].distanceKm, 30, "Newest should be first")
        XCTAssertEqual(loaded[1].distanceKm, 20, "Middle should be second")
        XCTAssertEqual(loaded[2].distanceKm, 10, "Oldest should be last")
    }

    // MARK: - Delete all

    func test_deleteAll_removesAllTrips() {
        store.save(makeSummary(distanceKm: 50))
        store.save(makeSummary(distanceKm: 75))

        store.deleteAll()

        let loaded = store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    func test_deleteAll_onEmptyStore_doesNotCrash() {
        store.deleteAll()
        let loaded = store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Round-trip fidelity

    func test_roundTrip_preservesAllFields() {
        let trip = TripSummary(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 7200,
            distanceKm: 142.3,
            avgSpeedKmh: 63.5,
            maxSpeedKmh: 148.2,
            elevationGainM: 890
        )
        store.save(trip)

        let loaded = store.loadAll().first!
        XCTAssertEqual(loaded.id, trip.id)
        XCTAssertEqual(loaded.duration, 7200)
        XCTAssertEqual(loaded.distanceKm, 142.3, accuracy: 0.001)
        XCTAssertEqual(loaded.avgSpeedKmh, 63.5, accuracy: 0.001)
        XCTAssertEqual(loaded.maxSpeedKmh, 148.2, accuracy: 0.001)
        XCTAssertEqual(loaded.elevationGainM, 890, accuracy: 0.001)
    }

    // MARK: - Separate instances share storage

    func test_separateInstances_shareDefaults() {
        let store1 = TripHistoryStore(defaults: defaults)
        let store2 = TripHistoryStore(defaults: defaults)

        store1.save(makeSummary(distanceKm: 99))

        let loaded = store2.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.distanceKm, 99)
    }

    // MARK: - Helpers

    private func makeSummary(
        date: Date = Date(),
        distanceKm: Double
    ) -> TripSummary {
        TripSummary(
            date: date,
            duration: 3600,
            distanceKm: distanceKm,
            avgSpeedKmh: 50,
            maxSpeedKmh: 120,
            elevationGainM: 300
        )
    }
}
