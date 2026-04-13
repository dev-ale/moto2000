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
public actor NavigationService: PayloadService {
    private let routeEngine: any RouteEngine
    private let locationProvider: any LocationProvider
    private let channel: PayloadChannel
    public nonisolated let navDataPayloads: AsyncStream<Data>

    public nonisolated var payloadStream: AsyncStream<Data> { navDataPayloads }

    private var consumerTask: Task<Void, Never>?
    private var tracker: RouteTracker?
    private var currentDestination: NavigationRoute.LocationCoordinate?
    private var startObserver: NSObjectProtocol?
    private var stopObserver: NSObjectProtocol?

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

    /// PayloadService no-op start: navigation doesn't begin until a
    /// destination is set via `scramNavigationStartRequested`. We hook
    /// the notification here so the registry can manage lifecycle the
    /// same way as every other service.
    public func start() async {
        NSLog("[NAV] NavigationService.start() — installing notification observers")
        let center = NotificationCenter.default
        let startName = Notification.Name("scramNavigationStartRequested")
        let stopName = Notification.Name("scramNavigationStopRequested")
        startObserver = center.addObserver(
            forName: startName, object: nil, queue: nil
        ) { [weak self] note in
            NSLog("[NAV] received scramNavigationStartRequested")
            guard let info = note.userInfo,
                  let lat = info["latitude"] as? Double,
                  let lon = info["longitude"] as? Double else {
                NSLog("[NAV] notification missing lat/lon; userInfo=%@",
                      String(describing: note.userInfo))
                return
            }
            let dest = NavigationRoute.LocationCoordinate(latitude: lat, longitude: lon)
            Task { [weak self] in
                do {
                    try await self?.start(destination: dest)
                } catch {
                    NSLog("[NAV] start(destination:) threw: %@",
                          String(describing: error))
                }
            }
        }
        stopObserver = center.addObserver(
            forName: stopName, object: nil, queue: nil
        ) { [weak self] _ in
            NSLog("[NAV] received scramNavigationStopRequested")
            Task { [weak self] in
                await self?.stopRoute()
            }
        }
    }

    /// Stop the active route but leave the service (and its
    /// notification observers) running so the next start request still
    /// works. Distinct from ``stop()`` which is the full PayloadService
    /// shutdown that ``RideSession`` calls on link drop.
    public func stopRoute() {
        consumerTask?.cancel()
        consumerTask = nil
        tracker = nil
        currentDestination = nil

        let idle = NavData(
            latitudeE7: 0,
            longitudeE7: 0,
            speedKmhX10: 0,
            headingDegX10: 0,
            distanceToManeuverMeters: 0,
            maneuver: .none,
            streetName: "",
            etaMinutes: 0,
            remainingKmX10: 0
        )
        if let data = try? ScreenPayloadCodec.encode(.navigation(idle, flags: [])) {
            channel.emit(data)
        }
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
        NSLog("[NAV] start(destination: %.5f, %.5f)",
              destination.latitude, destination.longitude)
        guard consumerTask == nil else {
            NSLog("[NAV] start(destination:) skipped — consumer already running")
            return
        }
        currentDestination = destination

        // Grab the provider's sample stream once and split it into two
        // stages: "first sample" (used as origin) and "remaining
        // samples" (fed to the tracker). Because AsyncStream iteration
        // is single-consumer, we do both in the same task.
        let stream = locationProvider.samples
        let engine = routeEngine
        let ch = channel
        let dest = destination

        let provider = locationProvider
        let task = Task { [weak self] in
            // Prefer the provider's cached latest sample so we don't
            // contend with other consumers iterating the stream (which
            // can stall the route for minutes when other services are
            // already draining samples).
            var iterator = stream.makeAsyncIterator()
            let firstFix: LocationSample
            if let cached = provider.latestSample {
                Self.publishStatus("using cached GPS fix")
                firstFix = cached
            } else {
                Self.publishStatus("waiting for first GPS fix…")
                guard let next = await iterator.next() else {
                    Self.publishStatus("no GPS fix; aborting")
                    return
                }
                firstFix = next
            }
            let origin = NavigationRoute.LocationCoordinate(
                latitude: firstFix.latitude,
                longitude: firstFix.longitude
            )
            Self.publishStatus(String(format: "computing route from %.4f,%.4f",
                                      firstFix.latitude, firstFix.longitude))
            let route: NavigationRoute
            do {
                route = try await engine.calculateRoute(from: origin, to: dest)
            } catch {
                Self.publishStatus("route error: \(error)")
                return
            }
            Self.publishStatus(String(
                format: "route: %.0f m, %.0f s, %d steps",
                route.totalDistanceMeters,
                route.expectedTravelTimeSeconds,
                route.steps.count
            ))
            Self.publishRouteSummary(
                distanceMeters: route.totalDistanceMeters,
                durationSeconds: route.expectedTravelTimeSeconds
            )
            let localTracker = RouteTracker(route: route)
            await self?.setTracker(localTracker)

            // Emit a payload for the first sample too, so consumers see
            // one state per location sample starting from sample #0.
            if let data = await Self.encode(sample: firstFix, tracker: localTracker) {
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
            // Loop ended (arrival or task cancellation). Don't finish
            // the channel here — RideSession is iterating it for the
            // session lifetime and stopRoute() needs to push a final
            // synthetic .none payload so the firmware nav screen
            // returns to the idle text.
        }
        consumerTask = task
    }

    public func stop() {
        stopRoute()
        if let s = startObserver {
            NotificationCenter.default.removeObserver(s)
            startObserver = nil
        }
        if let s = stopObserver {
            NotificationCenter.default.removeObserver(s)
            stopObserver = nil
        }
        channel.finish()
    }

    // MARK: - Private

    private func setTracker(_ tracker: RouteTracker) {
        self.tracker = tracker
    }

    /// Posts a one-line status update on a NotificationCenter channel
    /// the iOS UI can subscribe to. Keeps the diagnostic loop visible
    /// without needing an external log stream.
    private static func publishStatus(_ message: String) {
        NSLog("[NAV] %@", message)
        NotificationCenter.default.post(
            name: Notification.Name("scramNavigationStatusUpdate"),
            object: nil,
            userInfo: ["message": message]
        )
    }

    /// Publish a structured route summary so the iOS card can show
    /// distance, duration, and ETA without parsing log strings.
    private static func publishRouteSummary(
        distanceMeters: Double,
        durationSeconds: Double
    ) {
        NotificationCenter.default.post(
            name: Notification.Name("scramNavigationRouteReady"),
            object: nil,
            userInfo: [
                "distanceMeters": distanceMeters,
                "durationSeconds": durationSeconds,
                "computedAt": Date(),
            ]
        )
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
