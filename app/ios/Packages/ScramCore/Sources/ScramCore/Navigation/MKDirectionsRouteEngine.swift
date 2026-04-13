#if canImport(MapKit)
import Foundation
import MapKit
import BLEProtocol

/// Production ``RouteEngine`` that wraps `MKDirections`.
///
/// Kept behind `#if canImport(MapKit)` so the rest of the package
/// (tracker, service, fixtures) builds on macOS hosts without MapKit
/// linked in. All the actual logic on the hot path — step advance,
/// distance calculations, BLE encoding — lives outside this file and
/// is exercised by ``StaticRouteEngine``-driven unit tests.
///
/// Maneuver mapping strategy: `MKRoute.Step` does not expose a
/// structured maneuver enum on iOS, so we fall back to simple keyword
/// heuristics over `step.instructions`. This is intentionally
/// conservative — when in doubt we return ``ManeuverType/straight`` and
/// let the rider see the street name text, which is more useful than a
/// wrong arrow glyph.
public struct MKDirectionsRouteEngine: RouteEngine {
    public init() {}

    public func calculateRoute(
        from origin: NavigationRoute.LocationCoordinate,
        to destination: NavigationRoute.LocationCoordinate
    ) async throws -> NavigationRoute {
        let request = MKDirections.Request()
        request.transportType = .automobile
        request.source = MKMapItem(
            placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                latitude: origin.latitude, longitude: origin.longitude
            ))
        )
        request.destination = MKMapItem(
            placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                latitude: destination.latitude, longitude: destination.longitude
            ))
        )

        let directions = MKDirections(request: request)
        let response: MKDirections.Response
        do {
            response = try await directions.calculate()
        } catch {
            throw RouteEngineError.underlying(String(describing: error))
        }
        guard let route = response.routes.first else {
            throw RouteEngineError.noRoutes
        }

        let steps: [NavigationRoute.Step] = route.steps.map { step in
            let start = step.polyline.points()[0]
            let count = step.polyline.pointCount
            let endIdx = max(count - 1, 0)
            let end = step.polyline.points()[endIdx]
            return NavigationRoute.Step(
                maneuver: Self.maneuverFromInstructions(step.instructions),
                streetName: Self.streetFromInstructions(step.instructions),
                distanceMeters: step.distance,
                startLocation: NavigationRoute.LocationCoordinate(
                    latitude: start.coordinate.latitude,
                    longitude: start.coordinate.longitude
                ),
                endLocation: NavigationRoute.LocationCoordinate(
                    latitude: end.coordinate.latitude,
                    longitude: end.coordinate.longitude
                )
            )
        }

        let nav = NavigationRoute(
            steps: steps,
            totalDistanceMeters: route.distance,
            expectedTravelTimeSeconds: route.expectedTravelTime
        )

        // Verbose route dump so the rider can verify routing in console
        // (Console.app or Xcode device log filtered by [NAV]).
        NSLog("[NAV] route: %.0f m, %.0f s, %d steps",
              route.distance, route.expectedTravelTime, steps.count)
        for (i, step) in steps.enumerated() {
            NSLog("[NAV]   %2d: %@ — %.0f m — %@",
                  i,
                  String(describing: step.maneuver),
                  step.distanceMeters,
                  step.streetName.isEmpty ? "(no street)" : step.streetName)
        }

        return nav
    }

    // MARK: - Heuristics

    /// Map an instruction string to a ``ManeuverType``. Exposed as
    /// internal for unit testing.
    static func maneuverFromInstructions(_ instructions: String) -> ManeuverType {
        let lower = instructions.lowercased()
        if lower.contains("arrive") || lower.contains("destination") {
            return .arrive
        }
        if lower.contains("u-turn") || lower.contains("u turn") {
            return lower.contains("right") ? .uTurnRight : .uTurnLeft
        }
        if lower.contains("roundabout") || lower.contains("traffic circle") {
            return lower.contains("exit") ? .roundaboutExit : .roundaboutEnter
        }
        if lower.contains("merge") { return .merge }
        if lower.contains("fork") {
            return lower.contains("right") ? .forkRight : .forkLeft
        }
        if lower.contains("sharp") && lower.contains("left") { return .sharpLeft }
        if lower.contains("sharp") && lower.contains("right") { return .sharpRight }
        if lower.contains("slight") && lower.contains("left") { return .slightLeft }
        if lower.contains("slight") && lower.contains("right") { return .slightRight }
        if lower.contains("left") { return .left }
        if lower.contains("right") { return .right }
        return .straight
    }

    /// Extract a plausible street name from an instruction string. MapKit
    /// returns phrases like "Turn right onto Aeschengraben" or "Continue
    /// on Hauptstrasse"; we strip the verb prefix and keep the rest.
    static func streetFromInstructions(_ instructions: String) -> String {
        let separators: [String] = [" onto ", " on ", " toward "]
        for sep in separators {
            if let range = instructions.range(of: sep) {
                return String(instructions[range.upperBound...])
            }
        }
        return instructions
    }
}
#endif
