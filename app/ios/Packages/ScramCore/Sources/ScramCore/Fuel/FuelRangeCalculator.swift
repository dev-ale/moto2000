import Foundation

/// Pure functions that compute fuel range estimates from fill history
/// and current distance driven since the last fill.
///
/// Consumption formula:
///   averageConsumption = totalFuelConsumed / totalDistanceDriven
///   (only across full fills, since partial fills don't tell us
///    how much fuel was actually in the tank)
///
/// If no full fills exist, consumption is unknown and all estimates
/// return nil (which maps to the 0xFFFF wire sentinel).
public enum FuelRangeCalculator {

    /// Result of a fuel estimate computation. All fields are nil when
    /// consumption cannot be determined (no full fills).
    public struct Estimate: Equatable, Sendable {
        /// Average fuel consumption in mL/km, or nil if unknown.
        public var consumptionMlPerKm: Double?
        /// Estimated fuel remaining in mL, or nil if unknown.
        public var remainingMl: Double?
        /// Estimated range in km, or nil if unknown.
        public var rangeKm: Double?
        /// Tank percentage (0..100), or nil if unknown.
        public var tankPercent: Double?
    }

    /// Compute the average consumption in mL/km from fill history.
    ///
    /// Only full fills contribute: each full fill tells us the rider
    /// consumed `amountMilliliters` of fuel over `distanceSinceLastFillKm`.
    /// We sum all fuel and all distance across full fills, then divide.
    ///
    /// Returns nil if there are no full fills or total distance is zero.
    public static func averageConsumptionMlPerKm(
        fills: [FuelFillEntry]
    ) -> Double? {
        let fullFills = fills.filter(\.isFull)
        guard !fullFills.isEmpty else { return nil }

        let totalFuel = fullFills.reduce(0.0) { $0 + $1.amountMilliliters }
        let totalDistance = fullFills.reduce(0.0) { $0 + $1.distanceSinceLastFillKm }
        guard totalDistance > 0 else { return nil }

        return totalFuel / totalDistance
    }

    /// Compute the full fuel estimate.
    ///
    /// - Parameters:
    ///   - fills: The fill history.
    ///   - currentDistanceSinceLastFillKm: Distance driven since the most
    ///     recent fill (tracked by the app via GPS).
    ///   - settings: Fuel settings (tank capacity).
    public static func estimate(
        fills: [FuelFillEntry],
        currentDistanceSinceLastFillKm: Double,
        settings: FuelSettings
    ) -> Estimate {
        guard let consumption = averageConsumptionMlPerKm(fills: fills) else {
            return Estimate()
        }

        // Fuel consumed since last fill
        let consumedSinceLastFill = consumption * currentDistanceSinceLastFillKm

        // Remaining fuel = tank capacity - consumed since last fill
        // (assumes last fill was a full tank; if not, this is an approximation)
        let remaining = max(settings.tankCapacityMl - consumedSinceLastFill, 0)

        // Range = remaining / consumption rate
        let range: Double
        if consumption > 0 {
            range = remaining / consumption
        } else {
            range = 0
        }

        // Tank percent
        let percent: Double
        if settings.tankCapacityMl > 0 {
            percent = min(max((remaining / settings.tankCapacityMl) * 100, 0), 100)
        } else {
            percent = 0
        }

        return Estimate(
            consumptionMlPerKm: consumption,
            remainingMl: remaining,
            rangeKm: range,
            tankPercent: percent
        )
    }
}
