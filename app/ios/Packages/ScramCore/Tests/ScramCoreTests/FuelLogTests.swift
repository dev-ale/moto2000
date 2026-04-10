import XCTest

@testable import ScramCore

final class FuelLogTests: XCTestCase {

    func test_addFill_persistsAndReturnsEntries() async throws {
        let store = InMemoryFuelLogStore()
        let log = FuelLog(store: store)

        let fill = FuelFillEntry(
            amountMilliliters: 10_000,
            distanceSinceLastFillKm: 250,
            isFull: true
        )
        try await log.addFill(fill)

        let entries = try await log.allEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.amountMilliliters, 10_000)
    }

    func test_multipleFills_sortedByDate() async throws {
        let store = InMemoryFuelLogStore()
        let log = FuelLog(store: store)

        let earlier = FuelFillEntry(
            date: Date(timeIntervalSince1970: 1000),
            amountMilliliters: 5000,
            distanceSinceLastFillKm: 100,
            isFull: true
        )
        let later = FuelFillEntry(
            date: Date(timeIntervalSince1970: 2000),
            amountMilliliters: 8000,
            distanceSinceLastFillKm: 200,
            isFull: true
        )
        // Add later first to verify sorting
        try await log.addFill(later)
        try await log.addFill(earlier)

        let entries = try await log.allEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.date, earlier.date)
    }

    func test_clear_removesAllEntries() async throws {
        let store = InMemoryFuelLogStore()
        let log = FuelLog(store: store)

        try await log.addFill(FuelFillEntry(
            amountMilliliters: 5000,
            distanceSinceLastFillKm: 100,
            isFull: true
        ))

        try await log.clear()
        let entries = try await log.allEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    func test_persistenceRoundTrip_throughInMemoryStore() async throws {
        let store = InMemoryFuelLogStore()

        // Write through one FuelLog instance
        let log1 = FuelLog(store: store)
        let fill = FuelFillEntry(
            amountMilliliters: 12_000,
            distanceSinceLastFillKm: 300,
            isFull: true
        )
        try await log1.addFill(fill)

        // Read through a fresh FuelLog instance sharing the same store
        let log2 = FuelLog(store: store)
        let entries = try await log2.allEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, fill.id)
        XCTAssertEqual(entries.first?.amountMilliliters, 12_000)
    }

    func test_averageConsumption_delegatesToCalculator() async throws {
        let store = InMemoryFuelLogStore()
        let log = FuelLog(store: store)

        try await log.addFill(FuelFillEntry(
            amountMilliliters: 10_000,
            distanceSinceLastFillKm: 250,
            isFull: true
        ))

        let consumption = try await log.averageConsumptionMlPerKm()
        XCTAssertEqual(consumption!, 40, accuracy: 0.01)
    }

    func test_emptyLog_averageConsumptionIsNil() async throws {
        let store = InMemoryFuelLogStore()
        let log = FuelLog(store: store)

        let consumption = try await log.averageConsumptionMlPerKm()
        XCTAssertNil(consumption)
    }
}
