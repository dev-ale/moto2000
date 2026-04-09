import Foundation
import BLEProtocol

/// A pre-computed driving route made of ordered steps.
///
/// This is the pure value type that flows through the navigation
/// pipeline. It is intentionally framework-free: no MapKit, no
/// CoreLocation — everything is plain `Double`s so the type can be
/// serialised to JSON for test fixtures and unit-tested on macOS hosts.
///
/// `MKDirectionsRouteEngine` produces values of this type from a live
/// `MKDirections` response; `StaticRouteEngine` produces them from a
/// bundled JSON fixture. Everything downstream (``RouteTracker``,
/// ``NavigationService``) deals with `NavigationRoute` only.
public struct NavigationRoute: Sendable, Equatable, Codable {
    /// Plain lat/lon value type. We do not import CoreLocation here
    /// because CoreLocation's types are not `Codable` and we want this
    /// file to build on Linux/macOS hosts for tests.
    public struct LocationCoordinate: Sendable, Equatable, Codable {
        public var latitude: Double
        public var longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// One maneuver step of the route.
    ///
    /// The distance/time fields are carried through from the upstream
    /// directions service so we do not have to re-derive them, but the
    /// tracker recomputes distance-to-next-maneuver from live GPS so it
    /// stays correct even if the rider drifts off-route slightly.
    public struct Step: Sendable, Equatable, Codable {
        public var maneuver: ManeuverType
        /// Street name as the rider sees it on screen. Must be ≤ 31
        /// UTF-8 bytes to fit the `nav_data_t` fixed-width field; the
        /// tracker/service re-clamps on the way out, but keeping this
        /// invariant at the source simplifies callers.
        public var streetName: String
        /// Total length of this step in metres.
        public var distanceMeters: Double
        public var startLocation: LocationCoordinate
        public var endLocation: LocationCoordinate

        public init(
            maneuver: ManeuverType,
            streetName: String,
            distanceMeters: Double,
            startLocation: LocationCoordinate,
            endLocation: LocationCoordinate
        ) {
            self.maneuver = maneuver
            self.streetName = streetName
            self.distanceMeters = distanceMeters
            self.startLocation = startLocation
            self.endLocation = endLocation
        }
    }

    public var steps: [Step]
    public var totalDistanceMeters: Double
    public var expectedTravelTimeSeconds: Double

    public init(
        steps: [Step],
        totalDistanceMeters: Double,
        expectedTravelTimeSeconds: Double
    ) {
        self.steps = steps
        self.totalDistanceMeters = totalDistanceMeters
        self.expectedTravelTimeSeconds = expectedTravelTimeSeconds
    }
}

// MARK: - ManeuverType Codable bridge

/// Codable bridge for ``ManeuverType`` so route fixtures can be written
/// as human-readable JSON strings rather than opaque raw bytes.
extension ManeuverType: @retroactive Decodable, @retroactive Encodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let match = ManeuverType.fromJSONName(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unknown maneuver name: \(raw)"
            )
        }
        self = match
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(jsonName)
    }

    public var jsonName: String {
        switch self {
        case .none: return "none"
        case .straight: return "straight"
        case .slightLeft: return "slightLeft"
        case .left: return "left"
        case .sharpLeft: return "sharpLeft"
        case .uTurnLeft: return "uTurnLeft"
        case .slightRight: return "slightRight"
        case .right: return "right"
        case .sharpRight: return "sharpRight"
        case .uTurnRight: return "uTurnRight"
        case .roundaboutEnter: return "roundaboutEnter"
        case .roundaboutExit: return "roundaboutExit"
        case .merge: return "merge"
        case .forkLeft: return "forkLeft"
        case .forkRight: return "forkRight"
        case .arrive: return "arrive"
        }
    }

    static func fromJSONName(_ name: String) -> ManeuverType? {
        ManeuverType.allCases.first { $0.jsonName == name }
    }
}
