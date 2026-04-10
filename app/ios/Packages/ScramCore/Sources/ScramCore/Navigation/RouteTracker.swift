import Foundation
import BLEProtocol
import RideSimulatorKit

/// Immutable view of what the rider should see right now, derived from
/// the route + the latest GPS sample. Encodes cleanly into `nav_data_t`.
public struct NavigationState: Sendable, Equatable {
    public var currentStepIndex: Int
    /// Straight-line distance, in metres, from the rider's current
    /// position to the *end* of the current step (the point where the
    /// next maneuver happens).
    public var distanceToNextManeuverMeters: Double
    public var remainingDistanceMeters: Double
    public var etaMinutes: UInt16
    public var currentHeadingDegX10: UInt16
    public var currentSpeedKmhX10: UInt16
    public var currentLatitudeE7: Int32
    public var currentLongitudeE7: Int32
    public var currentManeuver: ManeuverType
    public var currentStreetName: String

    public init(
        currentStepIndex: Int,
        distanceToNextManeuverMeters: Double,
        remainingDistanceMeters: Double,
        etaMinutes: UInt16,
        currentHeadingDegX10: UInt16,
        currentSpeedKmhX10: UInt16,
        currentLatitudeE7: Int32,
        currentLongitudeE7: Int32,
        currentManeuver: ManeuverType,
        currentStreetName: String
    ) {
        self.currentStepIndex = currentStepIndex
        self.distanceToNextManeuverMeters = distanceToNextManeuverMeters
        self.remainingDistanceMeters = remainingDistanceMeters
        self.etaMinutes = etaMinutes
        self.currentHeadingDegX10 = currentHeadingDegX10
        self.currentSpeedKmhX10 = currentSpeedKmhX10
        self.currentLatitudeE7 = currentLatitudeE7
        self.currentLongitudeE7 = currentLongitudeE7
        self.currentManeuver = currentManeuver
        self.currentStreetName = currentStreetName
    }
}

/// Stateful actor that consumes a location stream and maintains a
/// ``NavigationState`` relative to a given ``NavigationRoute``.
///
/// The tracker is a pure function of (route, location history) — it does
/// not import MapKit or CoreLocation. All distances use haversine.
///
/// Step-advance rule: when the rider is within ``arrivalToleranceMeters``
/// of the current step's end point, the tracker advances to the next
/// step.
///
/// Off-route rule: when the rider is more than ``offRouteThresholdMeters``
/// from the nearest step segment for ``offRouteConsecutiveThreshold``
/// consecutive updates, ``isOffRoute`` becomes true.
///
/// Arrival rule: when the tracker is on the last step and the rider is
/// within ``arrivalToleranceMeters`` of the destination, ``hasArrived``
/// becomes true.
public actor RouteTracker {
    /// Metres of slack around each step end-point; when the rider gets
    /// closer than this we consider the step complete.
    public static let arrivalToleranceMeters: Double = 15.0

    /// Distance threshold in metres beyond which the rider is considered
    /// off-route (measured from nearest point on any step segment).
    public static let offRouteThresholdMeters: Double = 100.0

    /// Number of consecutive off-route samples required before
    /// ``isOffRoute`` fires. At ~1 Hz GPS this is roughly 10 seconds.
    public static let offRouteConsecutiveThreshold: Int = 10

    private var route: NavigationRoute
    private var currentStepIndex: Int = 0
    private var consecutiveOffRouteCount: Int = 0

    /// True when the rider has been off-route for enough consecutive
    /// samples. Reset when a new route is loaded or the rider returns.
    public private(set) var isOffRoute: Bool = false

    /// True when the rider has arrived at the destination (last step,
    /// within tolerance). Once set it stays true for this tracker.
    public private(set) var hasArrived: Bool = false

    public init(route: NavigationRoute) {
        self.route = route
    }

    /// Replace the current route (used after a reroute). Resets all
    /// off-route and arrival state.
    public func replaceRoute(_ newRoute: NavigationRoute) {
        self.route = newRoute
        self.currentStepIndex = 0
        self.consecutiveOffRouteCount = 0
        self.isOffRoute = false
        self.hasArrived = false
    }

    /// Feed the next GPS sample in. Returns the updated ``NavigationState``.
    ///
    /// Does not mutate on a zero-length route (returns a sentinel state
    /// with `currentStepIndex == 0` and distances = 0).
    public func update(with location: LocationSample) -> NavigationState {
        guard !route.steps.isEmpty else {
            return NavigationState(
                currentStepIndex: 0,
                distanceToNextManeuverMeters: 0,
                remainingDistanceMeters: 0,
                etaMinutes: 0,
                currentHeadingDegX10: 0,
                currentSpeedKmhX10: 0,
                currentLatitudeE7: Self.latLonE7(location.latitude),
                currentLongitudeE7: Self.latLonE7(location.longitude),
                currentManeuver: .none,
                currentStreetName: ""
            )
        }

        advanceStepIfNeeded(for: location)

        let step = route.steps[currentStepIndex]
        let distToNext = Self.haversineMeters(
            lat1: location.latitude, lon1: location.longitude,
            lat2: step.endLocation.latitude, lon2: step.endLocation.longitude
        )

        // Remaining distance = current step's distance-to-end + sum of
        // all following steps. This is deterministic and does not
        // require projection onto a polyline.
        var remaining = distToNext
        if currentStepIndex + 1 < route.steps.count {
            for i in (currentStepIndex + 1)..<route.steps.count {
                remaining += route.steps[i].distanceMeters
            }
        }

        let eta = Self.estimateETA(remaining: remaining, route: route)

        let speedKmhX10 = Self.speedKmhX10(from: location.speedMps)
        let headingDegX10 = Self.headingDegX10(from: location.courseDegrees)

        updateOffRouteState(for: location)
        updateArrivalState(for: location)

        return NavigationState(
            currentStepIndex: currentStepIndex,
            distanceToNextManeuverMeters: distToNext,
            remainingDistanceMeters: remaining,
            etaMinutes: eta,
            currentHeadingDegX10: headingDegX10,
            currentSpeedKmhX10: speedKmhX10,
            currentLatitudeE7: Self.latLonE7(location.latitude),
            currentLongitudeE7: Self.latLonE7(location.longitude),
            currentManeuver: step.maneuver,
            currentStreetName: step.streetName
        )
    }

    // MARK: - Step advance

    private func advanceStepIfNeeded(for location: LocationSample) {
        // Advance when the rider is inside the arrival tolerance of the
        // current step's end. Never advance past the last step. We
        // deliberately do NOT use a "shoot-past / next-is-closer"
        // heuristic: on looping routes (end == start) that rule would
        // teleport the tracker straight to the final step on the very
        // first sample.
        while currentStepIndex < route.steps.count - 1 {
            let step = route.steps[currentStepIndex]
            let dToEnd = Self.haversineMeters(
                lat1: location.latitude, lon1: location.longitude,
                lat2: step.endLocation.latitude, lon2: step.endLocation.longitude
            )
            if dToEnd <= Self.arrivalToleranceMeters {
                currentStepIndex += 1
                continue
            }
            break
        }
    }

    // MARK: - ETA

    /// Scale the route's original expected travel time by fraction of
    /// distance remaining. Cheap, deterministic, good enough for BLE.
    private static func estimateETA(
        remaining: Double,
        route: NavigationRoute
    ) -> UInt16 {
        guard route.totalDistanceMeters > 0 else { return 0 }
        let fraction = min(max(remaining / route.totalDistanceMeters, 0), 1)
        let seconds = route.expectedTravelTimeSeconds * fraction
        let minutes = Int((seconds / 60.0).rounded())
        return UInt16(min(max(minutes, 0), 0xFFFE))
    }

    // MARK: - Arrival

    private func updateArrivalState(for location: LocationSample) {
        guard currentStepIndex == route.steps.count - 1 else { return }
        let lastStep = route.steps[currentStepIndex]
        let distToDest = Self.haversineMeters(
            lat1: location.latitude, lon1: location.longitude,
            lat2: lastStep.endLocation.latitude, lon2: lastStep.endLocation.longitude
        )
        if distToDest <= Self.arrivalToleranceMeters {
            hasArrived = true
        }
    }

    // MARK: - Off-route

    /// Compute the minimum haversine distance from `location` to any step
    /// segment (start→end). If that distance exceeds the threshold for
    /// enough consecutive samples, flag off-route.
    private func updateOffRouteState(for location: LocationSample) {
        let minDist = Self.minimumDistanceToRoute(
            lat: location.latitude,
            lon: location.longitude,
            steps: route.steps
        )
        if minDist > Self.offRouteThresholdMeters {
            consecutiveOffRouteCount += 1
            if consecutiveOffRouteCount >= Self.offRouteConsecutiveThreshold {
                isOffRoute = true
            }
        } else {
            consecutiveOffRouteCount = 0
            isOffRoute = false
        }
    }

    /// Minimum haversine distance from a point to any step segment.
    /// Uses a simple closest-of-(start, end) per segment — fine for
    /// the step granularity we have.
    static func minimumDistanceToRoute(
        lat: Double, lon: Double,
        steps: [NavigationRoute.Step]
    ) -> Double {
        var best = Double.infinity
        for step in steps {
            let dStart = haversineMeters(
                lat1: lat, lon1: lon,
                lat2: step.startLocation.latitude, lon2: step.startLocation.longitude
            )
            let dEnd = haversineMeters(
                lat1: lat, lon1: lon,
                lat2: step.endLocation.latitude, lon2: step.endLocation.longitude
            )
            best = min(best, dStart, dEnd)
        }
        return best
    }

    // MARK: - Pure helpers

    /// Haversine distance in metres between two lat/lon points.
    static func haversineMeters(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthRadiusM = 6_371_000.0
        let phi1 = lat1 * .pi / 180.0
        let phi2 = lat2 * .pi / 180.0
        let dphi = (lat2 - lat1) * .pi / 180.0
        let dlam = (lon2 - lon1) * .pi / 180.0
        let a = sin(dphi / 2) * sin(dphi / 2)
            + cos(phi1) * cos(phi2) * sin(dlam / 2) * sin(dlam / 2)
        let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
        return earthRadiusM * c
    }

    static func latLonE7(_ value: Double) -> Int32 {
        let scaled = (value * 1e7).rounded()
        return Int32(min(max(scaled, Double(Int32.min)), Double(Int32.max)))
    }

    static func speedKmhX10(from speedMps: Double) -> UInt16 {
        guard speedMps >= 0 else { return 0 }
        let raw = (speedMps * 3.6 * 10.0).rounded()
        return UInt16(min(max(raw, 0), 3000))
    }

    static func headingDegX10(from courseDegrees: Double) -> UInt16 {
        guard courseDegrees >= 0 else { return 0 }
        let raw = Int((courseDegrees * 10.0).rounded())
        let mod = ((raw % 3600) + 3600) % 3600
        return UInt16(mod)
    }
}
