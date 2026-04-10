import Foundation

/// A single manual fuel fill-up logged by the rider.
///
/// Design choice: we store `distanceSinceLastFillKm` rather than an absolute
/// odometer reading because the Scram 411 has no OBD port and no way to read
/// the odometer programmatically. The rider enters the distance they have
/// driven since their last fill (which the app can auto-populate from GPS
/// distance tracking). This keeps the model self-contained and avoids the
/// need for a global odometer synchronization step.
public struct FuelFillEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    /// Amount of fuel added in milliliters.
    public var amountMilliliters: Double
    /// Distance driven since the previous fill, in kilometers.
    public var distanceSinceLastFillKm: Double
    /// Whether this was a full fill-up (tank topped off).
    /// Only full fills are used for consumption averaging.
    public var isFull: Bool

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        amountMilliliters: Double,
        distanceSinceLastFillKm: Double,
        isFull: Bool
    ) {
        self.id = id
        self.date = date
        self.amountMilliliters = amountMilliliters
        self.distanceSinceLastFillKm = distanceSinceLastFillKm
        self.isFull = isFull
    }
}
