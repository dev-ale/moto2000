import XCTest

@testable import ScramCore

/// End-to-end fuel tracking scenarios simulating real-world usage.
/// Verifies that consumption adjusts correctly as fill history grows,
/// and that all displayed values (range, tank %, L/100km) are correct.
final class FuelEndToEndTests: XCTestCase {

    let scram411TankMl: Double = 15_000 // 15L tank

    // MARK: - Scenario: First ride ever (no fill history)

    func test_firstRide_usesDefaultConsumption() {
        let settings = FuelSettings(tankCapacityMl: scram411TankMl)
        let estimate = FuelRangeCalculator.estimate(
            fills: [],
            currentDistanceSinceLastFillKm: 0,
            settings: settings
        )

        // Default: 3.5 L/100km = 35 mL/km
        XCTAssertEqual(estimate.consumptionMlPerKm!, 35.0, accuracy: 0.01)
        // Range: 15000 / 35 = 428.6 km
        XCTAssertEqual(estimate.rangeKm!, 428.57, accuracy: 0.1)
        XCTAssertEqual(estimate.tankPercent!, 100.0, accuracy: 0.1)
    }

    func test_firstRide_afterDriving50km() {
        let settings = FuelSettings(tankCapacityMl: scram411TankMl)
        let estimate = FuelRangeCalculator.estimate(
            fills: [],
            currentDistanceSinceLastFillKm: 50,
            settings: settings
        )

        // consumed = 35 * 50 = 1750 mL, remaining = 13250 mL
        XCTAssertEqual(estimate.remainingMl!, 13_250, accuracy: 0.1)
        // range = 13250 / 35 = 378.6 km
        XCTAssertEqual(estimate.rangeKm!, 378.57, accuracy: 0.1)
        // tank% = 13250/15000 = 88.3%
        XCTAssertEqual(estimate.tankPercent!, 88.33, accuracy: 0.1)
    }

    // MARK: - Scenario: First full fill after 280km

    func test_afterFirstFullFill_consumptionCalibrates() {
        // Rider filled 12L after 280km
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 12_000,
                distanceSinceLastFillKm: 280,
                isFull: true
            ),
        ]
        let settings = FuelSettings(tankCapacityMl: scram411TankMl)

        // Consumption = 12000/280 = 42.86 mL/km = 4.29 L/100km
        let estimate = FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: 0,
            settings: settings
        )

        XCTAssertEqual(estimate.consumptionMlPerKm!, 42.857, accuracy: 0.01)
        // L/100km = 42.857 * 100 / 1000 = 4.29
        let litersPerHundredKm = estimate.consumptionMlPerKm! / 10.0
        XCTAssertEqual(litersPerHundredKm, 4.286, accuracy: 0.01)
        // Full tank range = 15000/42.857 = 350 km
        XCTAssertEqual(estimate.rangeKm!, 350.0, accuracy: 0.1)
        XCTAssertEqual(estimate.tankPercent!, 100.0, accuracy: 0.1)
    }

    // MARK: - Scenario: Second fill adjusts average

    func test_secondFullFill_averagesConsumption() {
        // Fill 1: 12L after 280km → 42.86 mL/km
        // Fill 2: 10L after 300km → 33.33 mL/km
        // Average: (12000+10000)/(280+300) = 22000/580 = 37.93 mL/km
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 12_000,
                distanceSinceLastFillKm: 280,
                isFull: true
            ),
            FuelFillEntry(
                amountMilliliters: 10_000,
                distanceSinceLastFillKm: 300,
                isFull: true
            ),
        ]
        let settings = FuelSettings(tankCapacityMl: scram411TankMl)

        let estimate = FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: 0,
            settings: settings
        )

        XCTAssertEqual(estimate.consumptionMlPerKm!, 37.931, accuracy: 0.01)
        // L/100km = 37.931 / 10 = 3.79
        let litersPerHundredKm = estimate.consumptionMlPerKm! / 10.0
        XCTAssertEqual(litersPerHundredKm, 3.793, accuracy: 0.01)
        // Range = 15000 / 37.931 = 395.4 km
        XCTAssertEqual(estimate.rangeKm!, 395.4, accuracy: 0.5)
    }

    // MARK: - Scenario: Mid-ride after second fill

    func test_midRide_afterSecondFill_150kmDriven() {
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 12_000,
                distanceSinceLastFillKm: 280,
                isFull: true
            ),
            FuelFillEntry(
                amountMilliliters: 10_000,
                distanceSinceLastFillKm: 300,
                isFull: true
            ),
        ]
        let settings = FuelSettings(tankCapacityMl: scram411TankMl)

        // Driven 150km since last fill
        let estimate = FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: 150,
            settings: settings
        )

        // consumption = 37.931 mL/km
        // consumed = 37.931 * 150 = 5689.7 mL
        // remaining = 15000 - 5689.7 = 9310.3 mL
        XCTAssertEqual(estimate.remainingMl!, 9310.3, accuracy: 1)
        // range = 9310.3 / 37.931 = 245.4 km
        XCTAssertEqual(estimate.rangeKm!, 245.4, accuracy: 0.5)
        // tank% = 9310.3 / 15000 = 62.1%
        XCTAssertEqual(estimate.tankPercent!, 62.07, accuracy: 0.1)
    }

    // MARK: - Scenario: Partial fill between full fills

    func test_partialFill_doesNotAffectConsumption() {
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 12_000,
                distanceSinceLastFillKm: 280,
                isFull: true
            ),
            // Partial top-up — should be ignored for consumption
            FuelFillEntry(
                amountMilliliters: 5_000,
                distanceSinceLastFillKm: 120,
                isFull: false
            ),
            FuelFillEntry(
                amountMilliliters: 10_000,
                distanceSinceLastFillKm: 300,
                isFull: true
            ),
        ]

        let consumption = FuelRangeCalculator.averageConsumptionMlPerKm(fills: fills)
        // Only full fills count: (12000+10000)/(280+300) = 37.93
        XCTAssertEqual(consumption!, 37.931, accuracy: 0.01)
    }

    // MARK: - Scenario: Display values match what the user sees

    func test_displayValues_litersPerHundredKm() {
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 10_500, // 10.5L
                distanceSinceLastFillKm: 300,
                isFull: true
            ),
        ]
        let settings = FuelSettings(tankCapacityMl: scram411TankMl)

        let estimate = FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: 0,
            settings: settings
        )

        // What the display shows:
        let consumptionMlPerKm = estimate.consumptionMlPerKm! // 35 mL/km
        let displayLPer100km = consumptionMlPerKm / 10.0 // 3.5 L/100km
        let displayRemainingLiters = estimate.remainingMl! / 1000.0 // 15.0 L
        let displayRangeKm = estimate.rangeKm! // 428.6 km

        XCTAssertEqual(displayLPer100km, 3.5, accuracy: 0.01)
        XCTAssertEqual(displayRemainingLiters, 15.0, accuracy: 0.1)
        XCTAssertEqual(displayRangeKm, 428.6, accuracy: 0.5)
    }

    // MARK: - Scenario: Nearly empty tank

    func test_nearlyEmptyTank() {
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 12_000,
                distanceSinceLastFillKm: 300,
                isFull: true
            ),
        ]
        let settings = FuelSettings(tankCapacityMl: scram411TankMl)

        // Driven 350km — almost at tank capacity
        let estimate = FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: 350,
            settings: settings
        )

        // consumption = 40 mL/km, consumed = 14000 mL
        // remaining = 15000-14000 = 1000 mL = 1.0L
        XCTAssertEqual(estimate.remainingMl!, 1000, accuracy: 0.1)
        // range = 1000/40 = 25 km
        XCTAssertEqual(estimate.rangeKm!, 25.0, accuracy: 0.1)
        // tank% = 1000/15000 = 6.67%
        XCTAssertEqual(estimate.tankPercent!, 6.67, accuracy: 0.1)
    }
}
