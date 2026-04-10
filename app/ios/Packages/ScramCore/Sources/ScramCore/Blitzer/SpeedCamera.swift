import Foundation

/// A single speed camera position with metadata.
///
/// This is a value type loaded from a local JSON database (OSM import
/// pipeline is a follow-up). The coordinate system is WGS-84.
public struct SpeedCamera: Sendable, Equatable, Codable {
    public var latitude: Double
    public var longitude: Double
    /// Speed limit at the camera in km/h, or `nil` if unknown.
    public var speedLimitKmh: UInt16?
    public var cameraType: CameraType

    public enum CameraType: String, Sendable, Codable, CaseIterable {
        case fixed, mobile, redLight, section, unknown
    }

    public init(
        latitude: Double,
        longitude: Double,
        speedLimitKmh: UInt16? = nil,
        cameraType: CameraType = .unknown
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.speedLimitKmh = speedLimitKmh
        self.cameraType = cameraType
    }
}
