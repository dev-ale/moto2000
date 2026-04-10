import Foundation

/// Tiny pure-function geographic helpers shared by RouteTracker, the
/// trip-stats accumulator, and any future code that needs to compute
/// distances between WGS-84 points without pulling in CoreLocation /
/// MapKit. Keeping these here means the helpers stay testable on macOS
/// hosts and in our Linux CI.
public enum GeoMath {
    /// Mean Earth radius in metres, IUGG-2006 value used by every other
    /// helper in this codebase.
    public static let earthRadiusMeters: Double = 6_371_000.0

    /// Great-circle distance in metres between two WGS-84 points using
    /// the haversine formula. Stable for the kinds of short consecutive
    /// GPS samples that scenario replay produces.
    public static func haversineMeters(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let phi1 = lat1 * .pi / 180.0
        let phi2 = lat2 * .pi / 180.0
        let dphi = (lat2 - lat1) * .pi / 180.0
        let dlam = (lon2 - lon1) * .pi / 180.0
        let a = sin(dphi / 2) * sin(dphi / 2)
            + cos(phi1) * cos(phi2) * sin(dlam / 2) * sin(dlam / 2)
        let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
        return earthRadiusMeters * c
    }
}
