import Foundation
import BLEProtocol
import RideSimulatorKit

/// Orchestrates a live navigation session.
///
/// On ``start(destination:)``:
///   1. Waits for the first ``LocationSample`` from the provider and uses
///      it as the route origin.
///   2. Calls the injected ``RouteEngine`` to compute a ``NavigationRoute``.
///   3. Creates a ``RouteTracker`` for that route.
///   4. Spawns a consumer task that drains the provider's `samples`
///      stream, feeds each sample into the tracker, and encodes the
///      resulting ``NavigationState`` into a BLE `nav_data_t` payload
///      which is yielded on ``navDataPayloads``.
///
/// ``stop()`` cancels the consumer and finishes the output stream.
///
/// This actor is deliberately free of MapKit imports — it only knows
/// about the pure ``RouteEngine`` protocol. Real MapKit integration lives
/// in ``MKDirectionsRouteEngine`` behind `#if canImport(MapKit)`.
public actor NavigationService {
    private let routeEngine: any RouteEngine
    private let locationProvider: any LocationProvider
    private let channel: PayloadChannel
    public nonisolated let navDataPayloads: AsyncStream<Data>

    private var consumerTask: Task<Void, Never>?
    private var tracker: RouteTracker?
    private var currentDestination: NavigationRoute.LocationCoordinate?

    public init(
        routeEngine: any RouteEngine,
        locationProvider: any LocationProvider
    ) {
        self.routeEngine = routeEngine
        self.locationProvider = locationProvider
        let ch = PayloadChannel()
        self.channel = ch
        self.navDataPayloads = ch.makeStream()
    }

    /// Compute a route from the first observed location to `destination`
    /// and begin emitting encoded BLE payloads as new samples land.
    ///
    /// While running, the service monitors off-route state: when the
    /// tracker flags ``RouteTracker/isOffRoute``, a new route is
    /// calculated from the rider's current position to the same
    /// destination and seamlessly swapped in.
    ///
    /// When the tracker detects arrival (last step, within tolerance)
    /// the session stops silently — no notification, no splash screen.
    public func start(destination: NavigationRoute.LocationCoordinate) async throws {
        guard consumerTask == nil else { return }
        currentDestination = destination

        // Grab the provider's sample stream once and split it into two
        // stages: "first sample" (used as origin) and "remaining
        // samples" (fed to the tracker). Because AsyncStream iteration
        // is single-consumer, we do both in the same task.
        let stream = locationProvider.samples
        let engine = routeEngine
        let ch = channel
        let dest = destination

        let task = Task { [weak self] in
            var iterator = stream.makeAsyncIterator()
            guard let first = await iterator.next() else {
                ch.finish()
                return
            }
            let origin = NavigationRoute.LocationCoordinate(
                latitude: first.latitude,
                longitude: first.longitude
            )
            let route: NavigationRoute
            do {
                route = try await engine.calculateRoute(from: origin, to: dest)
            } catch {
                ch.finish()
                return
            }
            let localTracker = RouteTracker(route: route)
            await self?.setTracker(localTracker)

            // Emit a payload for the first sample too, so consumers see
            // one state per location sample starting from sample #0.
            if let data = await Self.encode(sample: first, tracker: localTracker) {
                ch.emit(data)
            }

            while let sample = await iterator.next() {
                if Task.isCancelled { break }

                if let data = await Self.encode(sample: sample, tracker: localTracker) {
                    ch.emit(data)
                }

                // Arrival: silently stop the session.
                if await localTracker.hasArrived {
                    break
                }

                // Off-route: reroute from current position to same dest.
                if await localTracker.isOffRoute {
                    let newOrigin = NavigationRoute.LocationCoordinate(
                        latitude: sample.latitude,
                        longitude: sample.longitude
                    )
                    if let newRoute = try? await engine.calculateRoute(
                        from: newOrigin, to: dest
                    ) {
                        await localTracker.replaceRoute(newRoute)
                    }
                }
            }
            ch.finish()
        }
        consumerTask = task
    }

    public func stop() {
        consumerTask?.cancel()
        consumerTask = nil
        channel.finish()
    }

    // MARK: - Private

    private func setTracker(_ tracker: RouteTracker) {
        self.tracker = tracker
    }

    private static func encode(
        sample: LocationSample,
        tracker: RouteTracker
    ) async -> Data? {
        let state = await tracker.update(with: sample)
        let streetClamped = Self.clampStreet(state.currentStreetName)
        let nav = NavData(
            latitudeE7: state.currentLatitudeE7,
            longitudeE7: state.currentLongitudeE7,
            speedKmhX10: state.currentSpeedKmhX10,
            headingDegX10: state.currentHeadingDegX10,
            distanceToManeuverMeters: Self.clampMetres(state.distanceToNextManeuverMeters),
            maneuver: state.currentManeuver,
            streetName: streetClamped,
            etaMinutes: state.etaMinutes,
            remainingKmX10: Self.remainingKmX10(state.remainingDistanceMeters)
        )
        do {
            return try ScreenPayloadCodec.encode(.navigation(nav, flags: []))
        } catch {
            return nil
        }
    }

    private static func clampStreet(_ name: String) -> String {
        // nav_data_t stores a 32-byte fixed field; at most 31 UTF-8
        // bytes (+ NUL) fit. Trim from the end as needed.
        var bytes = Array(name.utf8)
        while bytes.count > 31 {
            bytes.removeLast()
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func clampMetres(_ value: Double) -> UInt16 {
        let rounded = value.rounded()
        if rounded.isNaN { return NavData.unknownU16 }
        if rounded < 0 { return 0 }
        // 0xFFFF is the "unknown" sentinel so we cap short of it.
        if rounded >= Double(UInt16.max) { return 0xFFFE }
        return UInt16(rounded)
    }

    private static func remainingKmX10(_ meters: Double) -> UInt16 {
        let km = meters / 1000.0
        let scaled = (km * 10.0).rounded()
        if scaled.isNaN { return NavData.unknownU16 }
        if scaled < 0 { return 0 }
        if scaled >= Double(UInt16.max) { return 0xFFFE }
        return UInt16(scaled)
    }
}
