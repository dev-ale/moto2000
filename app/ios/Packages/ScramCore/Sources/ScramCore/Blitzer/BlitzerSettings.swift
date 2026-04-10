import Foundation

/// User-configurable settings for the blitzer proximity alert.
public struct BlitzerSettings: Sendable, Codable, Equatable {
    /// Radius in metres within which a camera triggers an alert.
    public var alertRadiusMeters: Double

    /// Whether the blitzer alert system is enabled.
    public var enabled: Bool

    public init(alertRadiusMeters: Double = 500, enabled: Bool = true) {
        self.alertRadiusMeters = alertRadiusMeters
        self.enabled = enabled
    }
}
