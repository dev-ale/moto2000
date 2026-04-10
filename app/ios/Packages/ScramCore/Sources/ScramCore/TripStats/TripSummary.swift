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
    public var hasRoute: Bool

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        duration: TimeInterval,
        distanceKm: Double,
        avgSpeedKmh: Double,
        maxSpeedKmh: Double,
        elevationGainM: Double,
        hasRoute: Bool = false
    ) {
        self.id = id
        self.date = date
        self.duration = duration
        self.distanceKm = distanceKm
        self.avgSpeedKmh = avgSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.elevationGainM = elevationGainM
        self.hasRoute = hasRoute
    }

    // Custom decoder to support records saved before `hasRoute` was added.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        distanceKm = try container.decode(Double.self, forKey: .distanceKm)
        avgSpeedKmh = try container.decode(Double.self, forKey: .avgSpeedKmh)
        maxSpeedKmh = try container.decode(Double.self, forKey: .maxSpeedKmh)
        elevationGainM = try container.decode(Double.self, forKey: .elevationGainM)
        hasRoute = try container.decodeIfPresent(Bool.self, forKey: .hasRoute) ?? false
    }
}
