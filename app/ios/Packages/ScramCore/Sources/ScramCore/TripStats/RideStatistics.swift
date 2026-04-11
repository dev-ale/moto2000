import Foundation

/// Aggregated statistics across all recorded rides.
public struct RideStatistics: Sendable, Equatable {
    public let totalRides: Int
    public let totalDistanceKm: Double
    public let totalDurationHours: Double
    public let thisMonthDistanceKm: Double

    public init(
        totalRides: Int,
        totalDistanceKm: Double,
        totalDurationHours: Double,
        thisMonthDistanceKm: Double
    ) {
        self.totalRides = totalRides
        self.totalDistanceKm = totalDistanceKm
        self.totalDurationHours = totalDurationHours
        self.thisMonthDistanceKm = thisMonthDistanceKm
    }

    /// Computes aggregate ride statistics from an array of trip summaries.
    ///
    /// - Parameters:
    ///   - trips: The trip summaries to aggregate.
    ///   - now: The reference date used to determine "this month". Defaults to the current date.
    /// - Returns: A ``RideStatistics`` value with totals and current-month distance.
    public static func compute(
        from trips: [TripSummary],
        now: Date = Date()
    ) -> RideStatistics {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        var totalDistance = 0.0
        var totalDuration: TimeInterval = 0
        var thisMonthDistance = 0.0

        for trip in trips {
            totalDistance += trip.distanceKm
            totalDuration += trip.duration

            let tripMonth = calendar.component(.month, from: trip.date)
            let tripYear = calendar.component(.year, from: trip.date)
            if tripMonth == currentMonth && tripYear == currentYear {
                thisMonthDistance += trip.distanceKm
            }
        }

        return RideStatistics(
            totalRides: trips.count,
            totalDistanceKm: totalDistance,
            totalDurationHours: totalDuration / 3600.0,
            thisMonthDistanceKm: thisMonthDistance
        )
    }
}
