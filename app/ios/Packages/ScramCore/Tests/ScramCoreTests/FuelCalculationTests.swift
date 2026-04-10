import XCTest

@testable import ScramCore

final class FuelCalculationTests: XCTestCase {

    // MARK: - Partial fills

    func test_partialFills_doNotContributeToConsumption() {
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 5000,
                distanceSinceLastFillKm: 100,
                isFull: false
            ),
            FuelFillEntry(
                amountMilliliters: 3000,
                distanceSinceLastFillKm: 80,
                isFull: false
            ),
        ]

        let consumption = FuelRangeCalculator.averageConsumptionMlPerKm(fills: fills)
        XCTAssertNil(consumption, "partial fills alone should not produce a consumption estimate")
    }

    func test_partialFillsWithOneFullFill_usesOnlyFullFill() {
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 3000,
                distanceSinceLastFillKm: 50,
                isFull: false
            ),
            FuelFillEntry(
                amountMilliliters: 10_000,
                distanceSinceLastFillKm: 250,
                isFull: true
            ),
        ]

        let consumption = FuelRangeCalculator.averageConsumptionMlPerKm(fills: fills)
        XCTAssertNotNil(consumption)
        // 10000 mL / 250 km = 40 mL/km
        XCTAssertEqual(consumption!, 40.0, accuracy: 0.01)
    }

    // MARK: - Full fill calibration

    func test_fullFill_calibratesConsumption() {
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 10_000,
                distanceSinceLastFillKm: 250,
                isFull: true
            ),
        ]

        let consumption = FuelRangeCalculator.averageConsumptionMlPerKm(fills: fills)
        // 10000 mL / 250 km = 40 mL/km
        XCTAssertEqual(consumption!, 40.0, accuracy: 0.01)
    }

    func test_multipleFullFills_averagesConsumption() {
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 10_000,
                distanceSinceLastFillKm: 250,
                isFull: true
            ),
            FuelFillEntry(
                amountMilliliters: 8_000,
                distanceSinceLastFillKm: 200,
                isFull: true
            ),
        ]

        let consumption = FuelRangeCalculator.averageConsumptionMlPerKm(fills: fills)
        // (10000 + 8000) / (250 + 200) = 18000 / 450 = 40 mL/km
        XCTAssertEqual(consumption!, 40.0, accuracy: 0.01)
    }

    // MARK: - Range estimate

    func test_rangeEstimate_withFullTank() {
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 10_000,
                distanceSinceLastFillKm: 250,
                isFull: true
            ),
        ]
        let settings = FuelSettings(tankCapacityMl: 15_000)

        let estimate = FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: 0,
            settings: settings
        )

        // consumption = 40 mL/km, tank = 15000 mL
        // range = 15000 / 40 = 375 km
        XCTAssertEqual(estimate.rangeKm!, 375.0, accuracy: 0.1)
        XCTAssertEqual(estimate.tankPercent!, 100.0, accuracy: 0.1)
    }

    func test_rangeEstimate_afterDriving() {
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 10_000,
                distanceSinceLastFillKm: 250,
                isFull: true
            ),
        ]
        let settings = FuelSettings(tankCapacityMl: 15_000)

        let estimate = FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: 100,
            settings: settings
        )

        // consumption = 40 mL/km, consumed = 40 * 100 = 4000 mL
        // remaining = 15000 - 4000 = 11000 mL
        // range = 11000 / 40 = 275 km
        XCTAssertEqual(estimate.remainingMl!, 11_000.0, accuracy: 0.1)
        XCTAssertEqual(estimate.rangeKm!, 275.0, accuracy: 0.1)
    }

    func test_noFills_allEstimatesNil() {
        let estimate = FuelRangeCalculator.estimate(
            fills: [],
            currentDistanceSinceLastFillKm: 50,
            settings: FuelSettings(tankCapacityMl: 15_000)
        )

        XCTAssertNil(estimate.consumptionMlPerKm)
        XCTAssertNil(estimate.remainingMl)
        XCTAssertNil(estimate.rangeKm)
        XCTAssertNil(estimate.tankPercent)
    }

    func test_rangeEstimate_clampsAtZero() {
        let fills: [FuelFillEntry] = [
            FuelFillEntry(
                amountMilliliters: 10_000,
                distanceSinceLastFillKm: 250,
                isFull: true
            ),
        ]
        let settings = FuelSettings(tankCapacityMl: 15_000)

        // Drive further than the tank allows
        let estimate = FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: 500,
            settings: settings
        )

        // consumed = 40 * 500 = 20000 > 15000, clamped to 0
        XCTAssertEqual(estimate.remainingMl!, 0.0, accuracy: 0.1)
        XCTAssertEqual(estimate.rangeKm!, 0.0, accuracy: 0.1)
        XCTAssertEqual(estimate.tankPercent!, 0.0, accuracy: 0.1)
    }
}
