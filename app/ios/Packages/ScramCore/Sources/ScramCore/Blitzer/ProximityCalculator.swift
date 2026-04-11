import Foundation

/// Result of a proximity calculation against the camera database.
public struct ProximityResult: Sendable, Equatable {
    /// The nearest camera, if any cameras were provided.
    public var nearestCamera: SpeedCamera?
    /// Distance in metres to the nearest camera. `Double.infinity` if no cameras.
    public var distanceMeters: Double
    /// Whether the nearest camera is within the alert radius.
    public var isInAlertRange: Bool

    public init(nearestCamera: SpeedCamera? = nil,
                distanceMeters: Double = .infinity,
                isInAlertRange: Bool = false) {
        self.nearestCamera = nearestCamera
        self.distanceMeters = distanceMeters
        self.isInAlertRange = isInAlertRange
    }
}

/// Pure-function proximity calculator. Finds the nearest camera and
/// determines whether the alert should fire.
public enum ProximityCalculator {
    /// Maximum angle between rider heading and camera bearing for alert.
    /// ±60° cone — alerts when roughly heading toward the camera.
    public static let maxApproachAngle: Double = 60.0

    /// Finds the nearest camera to the given GPS position.
    ///
    /// - Parameters:
    ///   - cameras: List of cameras (typically pre-filtered to a bounding box).
    ///   - latitude: Current WGS-84 latitude.
    ///   - longitude: Current WGS-84 longitude.
    ///   - alertRadiusMeters: Radius within which the alert fires.
    ///   - riderHeadingDegrees: Current GPS course (0-360). Pass nil to
    ///     skip direction filtering (alerts on all cameras in radius).
    /// - Returns: `nil` if `cameras` is empty; otherwise, a result with the
    ///   nearest camera and whether it's within range.
    public static func findNearest(
        cameras: [SpeedCamera],
        latitude: Double,
        longitude: Double,
        alertRadiusMeters: Double,
        riderHeadingDegrees: Double? = nil
    ) -> ProximityResult? {
        guard !cameras.isEmpty else { return nil }

        var nearest: SpeedCamera?
        var bestDistance = Double.infinity

        for camera in cameras {
            let d = GeoMath.haversineMeters(
                lat1: latitude, lon1: longitude,
                lat2: camera.latitude, lon2: camera.longitude
            )

            // Direction filter: skip cameras we're not heading toward
            if let heading = riderHeadingDegrees, heading >= 0, d > 10 {
                let bearingToCamera = GeoMath.bearing(
                    lat1: latitude, lon1: longitude,
                    lat2: camera.latitude, lon2: camera.longitude
                )
                let angleDiff = GeoMath.angleDifference(heading, bearingToCamera)
                if angleDiff > maxApproachAngle {
                    continue // heading away or perpendicular — skip
                }
            }

            if d < bestDistance {
                bestDistance = d
                nearest = camera
            }
        }

        guard let nearest else {
            return ProximityResult(isInAlertRange: false)
        }

        return ProximityResult(
            nearestCamera: nearest,
            distanceMeters: bestDistance,
            isInAlertRange: bestDistance <= alertRadiusMeters
        )
    }
}
