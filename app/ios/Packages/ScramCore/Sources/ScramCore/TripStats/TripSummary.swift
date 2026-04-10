import Foundation

/// A persisted summary of a single completed ride.
///
/// Created from ``TripStatsAccumulator`` data when a ride session ends.
/// Stored by ``TripHistoryStore`` and displayed in the Fahrten tab.
public struct TripSummary: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let duration: TimeInterval
    public let distanceKm: Double
    public let avgSpeedKmh: Double
    public let maxSpeedKmh: Double
    public let elevationGainM: Double

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        duration: TimeInterval,
        distanceKm: Double,
        avgSpeedKmh: Double,
        maxSpeedKmh: Double,
        elevationGainM: Double
    ) {
        self.id = id
        self.date = date
        self.duration = duration
        self.distanceKm = distanceKm
        self.avgSpeedKmh = avgSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.elevationGainM = elevationGainM
    }
}
