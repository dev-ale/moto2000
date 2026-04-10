import Foundation

/// User-configurable fuel settings.
///
/// Persisted alongside the fill log. The tank capacity defaults to 13 000 mL
/// (13 L) which is the Scram 411's stock tank size.
public struct FuelSettings: Codable, Sendable, Equatable {
    /// Tank capacity in milliliters.
    public var tankCapacityMl: Double

    public init(tankCapacityMl: Double = 13_000) {
        self.tankCapacityMl = tankCapacityMl
    }
}
