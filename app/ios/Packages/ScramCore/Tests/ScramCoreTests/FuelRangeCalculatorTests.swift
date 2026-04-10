import XCTest

@testable import ScramCore

final class FuelRangeCalculatorTests: XCTestCase {

    // MARK: - No fills → unknown

    func test_noFills_returnsNil() {
        let estimate = FuelRangeCalculator.estimate(
            fills: [],
            currentDistanceSinceLastFillKm: 0,
            settings: FuelSettings()
        )
        // With default 3.5L/100km (35 mL/km), estimates are non-nil
        XCTAssertEqual(estimate.consumptionMlPerKm, 35.0)
        XCTAssertNotNil(estimate.remainingMl)
        XCTAssertNotNil(estimate.rangeKm)
        XCTAssertNotNil(estimate.tankPercent)
    }

    func test_noFullFills_usesDefault() {
        let partial = FuelFillEntry(
            amountMilliliters: 5000,
            distanceSinceLastFillKm: 100,
            isFull: false
        )
        let estimate = FuelRangeCalculator.estimate(
            fills: [partial],
            currentDistanceSinceLastFillKm: 0,
            settings: FuelSettings()
        )
        // Default 35 mL/km used when no full fills
        XCTAssertEqual(estimate.consumptionMlPerKm, 35.0)
    }

    // MARK: - Single full fill

    func test_singleFullFill_sensibleRange() {
        let fill = FuelFillEntry(
            amountMilliliters: 10_000,
            distanceSinceLastFillKm: 250,
            isFull: true
        )
        // Consumption = 10000 / 250 = 40 mL/km
        let estimate = FuelRangeCalculator.estimate(
            fills: [fill],
            currentDistanceSinceLastFillKm: 0,
            settings: FuelSettings(tankCapacityMl: 13_000)
        )
        XCTAssertEqual(estimate.consumptionMlPerKm!, 40, accuracy: 0.01)
        // Remaining = 13000 - (40 * 0) = 13000
        XCTAssertEqual(estimate.remainingMl!, 13_000, accuracy: 0.01)
        // Range = 13000 / 40 = 325
        XCTAssertEqual(estimate.rangeKm!, 325, accuracy: 0.01)
        // Tank = 100%
        XCTAssertEqual(estimate.tankPercent!, 100, accuracy: 0.01)
    }

    func test_singleFullFill_halfwayThrough() {
        let fill = FuelFillEntry(
            amountMilliliters: 10_000,
            distanceSinceLastFillKm: 250,
            isFull: true
        )
        // Consumption = 40 mL/km. At 125 km: consumed = 5000, remaining = 8000
        let estimate = FuelRangeCalculator.estimate(
            fills: [fill],
            currentDistanceSinceLastFillKm: 125,
            settings: FuelSettings(tankCapacityMl: 13_000)
        )
        XCTAssertEqual(estimate.remainingMl!, 8_000, accuracy: 0.01)
        XCTAssertEqual(estimate.rangeKm!, 200, accuracy: 0.01)
        // Tank % = 8000/13000 * 100 ≈ 61.5
        XCTAssertEqual(estimate.tankPercent!, 61.538, accuracy: 0.1)
    }

    // MARK: - Multiple fills → average consumption

    func test_multipleFills_averagesAcrossFullFills() {
        let fills = [
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
            FuelFillEntry(
                amountMilliliters: 5_000,
                distanceSinceLastFillKm: 100,
                isFull: false // partial, should be ignored
            ),
        ]
        // Average = (10000 + 8000) / (250 + 200) = 18000 / 450 = 40 mL/km
        let consumption = FuelRangeCalculator.averageConsumptionMlPerKm(fills: fills)
        XCTAssertEqual(consumption!, 40, accuracy: 0.01)
    }

    // MARK: - Edge cases

    func test_zeroDistance_returnsNil() {
        let fill = FuelFillEntry(
            amountMilliliters: 10_000,
            distanceSinceLastFillKm: 0,
            isFull: true
        )
        let consumption = FuelRangeCalculator.averageConsumptionMlPerKm(fills: [fill])
        XCTAssertNil(consumption)
    }

    func test_zeroFuel_returnsZeroConsumption() {
        let fill = FuelFillEntry(
            amountMilliliters: 0,
            distanceSinceLastFillKm: 100,
            isFull: true
        )
        let consumption = FuelRangeCalculator.averageConsumptionMlPerKm(fills: [fill])
        XCTAssertEqual(consumption!, 0, accuracy: 0.01)
    }

    func test_veryLargeDistance_remainingClampsToZero() {
        let fill = FuelFillEntry(
            amountMilliliters: 10_000,
            distanceSinceLastFillKm: 250,
            isFull: true
        )
        // Distance far exceeds tank capacity: consumed > capacity → remaining = 0
        let estimate = FuelRangeCalculator.estimate(
            fills: [fill],
            currentDistanceSinceLastFillKm: 1000,
            settings: FuelSettings(tankCapacityMl: 13_000)
        )
        XCTAssertEqual(estimate.remainingMl!, 0, accuracy: 0.01)
        XCTAssertEqual(estimate.rangeKm!, 0, accuracy: 0.01)
        XCTAssertEqual(estimate.tankPercent!, 0, accuracy: 0.01)
    }

    func test_tankPercentNeverExceeds100() {
        let fill = FuelFillEntry(
            amountMilliliters: 10_000,
            distanceSinceLastFillKm: 250,
            isFull: true
        )
        // At distance 0, remaining = 13000, percent should be exactly 100
        let estimate = FuelRangeCalculator.estimate(
            fills: [fill],
            currentDistanceSinceLastFillKm: 0,
            settings: FuelSettings(tankCapacityMl: 13_000)
        )
        XCTAssertLessThanOrEqual(estimate.tankPercent!, 100)
    }
}
