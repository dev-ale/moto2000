import Foundation

/// Boundary for "compute a driving route between two coordinates".
///
/// The real implementation is ``MKDirectionsRouteEngine`` which wraps
/// `MKDirections`. Tests inject ``StaticRouteEngine`` to avoid CoreLocation
/// / MapKit entirely. Everything downstream (``NavigationService``,
/// ``RouteTracker``) only ever sees this protocol and the pure
/// ``NavigationRoute`` value type.
public protocol RouteEngine: Sendable {
    func calculateRoute(
        from origin: NavigationRoute.LocationCoordinate,
        to destination: NavigationRoute.LocationCoordinate
    ) async throws -> NavigationRoute
}

public enum RouteEngineError: Error, Equatable, Sendable {
    /// The upstream directions service returned no usable routes.
    case noRoutes
    /// The upstream service failed; the associated string is a human
    /// readable description (we do not surface the concrete NSError so
    /// the protocol stays Sendable).
    case underlying(String)
}

/// A test-only ``RouteEngine`` that returns a pre-built route regardless
/// of origin / destination.
///
/// Intended for unit tests and scenario integration tests: build the
/// expected route from a JSON fixture, wrap it in this engine, plug it
/// into ``NavigationService`` and drive a scripted location stream.
public struct StaticRouteEngine: RouteEngine {
    private let fixedRoute: NavigationRoute

    public init(fixedRoute: NavigationRoute) {
        self.fixedRoute = fixedRoute
    }

    public func calculateRoute(
        from origin: NavigationRoute.LocationCoordinate,
        to destination: NavigationRoute.LocationCoordinate
    ) async throws -> NavigationRoute {
        fixedRoute
    }
}
