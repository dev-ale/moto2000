import BLEProtocol
import CoreLocation
import EventKit
import Foundation
#if canImport(MapKit)
import MapKit
#endif
import Observation
import RideSimulatorKit
import ScramCore

// swiftlint:disable file_length
// swiftlint:disable type_body_length
// Debug-only session that creates real providers and services without BLE,
// decodes each service's encoded payloads back to typed data, and publishes
// them for the ``DisplayPreviewView`` to render live.
@Observable
@MainActor
final class LivePreviewSession {

    // MARK: - Published screen data

    var latestSpeed: SpeedHeadingData?
    var latestCompass: CompassData?
    var latestTripStats: TripStatsData?
    var latestLeanAngle: LeanAngleData?
    var latestWeather: WeatherData?
    var latestMusic: MusicData?
    var latestClock: ClockData?
    var latestAltitude: AltitudeProfileData?
    var latestFuel: FuelData?
    var latestNav: NavData?
    var latestAppointment: AppointmentData?
    var latestIncomingCall: IncomingCallData?
    var latestBlitzer: BlitzerData?

    var activeScreenID: ScreenID = .speedHeading
    var leanCalibrated = false
    private var leanReferenceAngle: Double = 0

    /// The ordered list of screens the user can swipe through.
    let availableScreens: [ScreenID] = [
        .speedHeading,
        .compass,
        .navigation,
        .tripStats,
        .leanAngle,
        .clock,
        .altitude,
        .weather,
        .music,
        .fuelEstimate,
        .appointment,
    ]

    // MARK: - Internal state

    private var services: [Any] = []
    private var tasks: [Task<Void, Never>] = []
    private var isRunning = false
    private var locationProvider: RealLocationProvider?
    private var routeCollector: RouteCollector?

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let locationProvider = RealLocationProvider()
        self.locationProvider = locationProvider
        let motionProvider = RealMotionProvider()

        // Request permissions and start providers
        tasks.append(Task {
            await locationProvider.start()
            await motionProvider.start()

            // Request calendar permission upfront
            #if canImport(EventKit)
            let store = EKEventStore()
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                _ = try? await store.requestFullAccessToEvents()
            }
            #endif
        })

        let collector = RouteCollector()
        collector.start(provider: locationProvider)
        self.routeCollector = collector

        startLocationServices(locationProvider)
        startMotionServices(motionProvider)
        startClockService()
        startWeatherService()  // uses self.locationProvider set above
        startMusicService()
        startCalendarService()
        startCallService()
        startBlitzerService(locationProvider: locationProvider)
        startFuelService(locationProvider: locationProvider)
        listenForNavigation(locationProvider: locationProvider)
    }

    func startNavigation(latitude: Double, longitude: Double) {
        guard let locationProvider else { return }
        #if canImport(MapKit)
        let engine = MKDirectionsRouteEngine()
        startNavigation(
            latitude: latitude,
            longitude: longitude,
            routeEngine: engine,
            locationProvider: locationProvider
        )
        #endif
    }

    /// Calculate a route directly and build NavData without waiting for
    /// NavigationService's GPS stream. This avoids hanging when no GPS
    /// fix is available (common indoors or right after permission grant).
    func startNavigation(
        latitude: Double,
        longitude: Double,
        routeEngine: some RouteEngine,
        locationProvider: some LocationProvider
    ) {
        let dest = NavigationRoute.LocationCoordinate(
            latitude: latitude,
            longitude: longitude
        )
        tasks.append(Task { @MainActor [weak self] in
            let origin = await Self.resolveOrigin(from: locationProvider)

            let route: NavigationRoute
            do {
                route = try await routeEngine.calculateRoute(
                    from: origin, to: dest
                )
            } catch {
                self?.latestNav = Self.errorNavData(origin: origin)
                return
            }

            self?.latestNav = Self.navData(
                from: route, origin: origin
            )
        })
    }

    private static func resolveOrigin(
        from provider: some LocationProvider
    ) async -> NavigationRoute.LocationCoordinate {
        if let sample = await firstSample(from: provider, timeoutSeconds: 5) {
            return NavigationRoute.LocationCoordinate(
                latitude: sample.latitude, longitude: sample.longitude
            )
        }
        return NavigationRoute.LocationCoordinate(
            latitude: 47.56, longitude: 7.59
        )
    }

    private static func errorNavData(
        origin: NavigationRoute.LocationCoordinate
    ) -> NavData {
        NavData(
            latitudeE7: Int32(origin.latitude * 1e7),
            longitudeE7: Int32(origin.longitude * 1e7),
            speedKmhX10: 0,
            headingDegX10: 0,
            distanceToManeuverMeters: NavData.unknownU16,
            maneuver: .none,
            streetName: "Route error",
            etaMinutes: NavData.unknownU16,
            remainingKmX10: NavData.unknownU16
        )
    }

    private static func navData(
        from route: NavigationRoute,
        origin: NavigationRoute.LocationCoordinate
    ) -> NavData? {
        guard let firstStep = route.steps.first else { return nil }
        let etaMinutes = UInt16(min(
            route.expectedTravelTimeSeconds / 60.0,
            Double(UInt16.max - 1)
        ))
        let remainingKmX10 = UInt16(min(
            (route.totalDistanceMeters / 1000.0) * 10.0,
            Double(UInt16.max - 1)
        ))
        let distMeters = UInt16(min(
            firstStep.distanceMeters,
            Double(UInt16.max - 1)
        ))
        return NavData(
            latitudeE7: Int32(origin.latitude * 1e7),
            longitudeE7: Int32(origin.longitude * 1e7),
            speedKmhX10: 0,
            headingDegX10: 0,
            distanceToManeuverMeters: distMeters,
            maneuver: firstStep.maneuver,
            streetName: String(firstStep.streetName.prefix(31)),
            etaMinutes: etaMinutes,
            remainingKmX10: remainingKmX10
        )
    }

    private func listenForNavigation(locationProvider: RealLocationProvider) {
        // Check if navigation was already started before preview opened
        let defaults = UserDefaults.standard
        if let lat = defaults.object(forKey: "scramNav.lat") as? Double,
           let lon = defaults.object(forKey: "scramNav.lon") as? Double,
           defaults.bool(forKey: "scramNav.active") {
            startNavigation(latitude: lat, longitude: lon)
        }

        // Listen for future navigation starts
        tasks.append(Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: .scramNavigationStartRequested
            ) {
                guard let self,
                      let userInfo = notification.userInfo,
                      let lat = userInfo["latitude"] as? Double,
                      let lon = userInfo["longitude"] as? Double
                else { continue }
                self.startNavigation(latitude: lat, longitude: lon)
            }
        })
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        // Collect route points before tearing down
        let routePoints = routeCollector?.stop() ?? []
        routeCollector = nil

        // Save trip if we have stats
        if let tripData = latestTripStats {
            let tripId = UUID()
            var hasRoute = false

            // Save route if we have points
            if !routePoints.isEmpty {
                let routeStorage = RouteStorage()
                routeStorage.save(tripId: tripId, coordinates: routePoints)
                hasRoute = true
            }

            let summary = TripSummary(
                id: tripId,
                date: Date(),
                duration: TimeInterval(tripData.rideTimeSeconds),
                distanceKm: Double(tripData.distanceMeters) / 1000.0,
                avgSpeedKmh: Double(tripData.averageSpeedKmhX10) / 10.0,
                maxSpeedKmh: Double(tripData.maxSpeedKmhX10) / 10.0,
                elevationGainM: Double(tripData.ascentMeters),
                hasRoute: hasRoute
            )
            // Only save if distance > 100m
            if summary.distanceKm > 0.1 {
                let store = TripHistoryStore()
                store.save(summary)
            }
        }

        for task in tasks { task.cancel() }
        tasks.removeAll()
        stopAllServices()
        services.removeAll()
    }

    private static let screenNames: [ScreenID: String] = [
        .speedHeading: "Speed",
        .compass: "Compass",
        .tripStats: "Trip Stats",
        .leanAngle: "Lean Angle",
        .clock: "Clock",
        .altitude: "Altitude",
        .weather: "Weather",
        .music: "Music",
        .fuelEstimate: "Fuel",
        .navigation: "Navigation",
        .appointment: "Appointment",
        .incomingCall: "Incoming Call",
        .blitzer: "Blitzer"
    ]

    func displayName(for screenID: ScreenID) -> String {
        Self.screenNames[screenID] ?? "Unknown"
    }

    func calibrateLeanAngle() {
        if let current = latestLeanAngle {
            leanReferenceAngle = Double(current.currentLeanDegX10) / 10.0
            leanCalibrated = true
        } else {
            leanReferenceAngle = 0
            leanCalibrated = true
        }
    }

    // MARK: - Service creation helpers

    private func startLocationServices(_ locationProvider: RealLocationProvider) {
        let speedService = SpeedHeadingService(provider: locationProvider)
        speedService.start()
        services.append(speedService)
        subscribe(to: speedService.encodedPayloads) { [weak self] payload in
            if case .speedHeading(let decoded, _) = payload { self?.latestSpeed = decoded }
        }
        let compassService = CompassService(provider: locationProvider)
        compassService.start()
        services.append(compassService)
        subscribe(to: compassService.encodedPayloads) { [weak self] payload in
            if case .compass(let decoded, _) = payload { self?.latestCompass = decoded }
        }
        let tripService = TripStatsService(provider: locationProvider)
        tripService.start()
        services.append(tripService)
        subscribe(to: tripService.payloads) { [weak self] payload in
            if case .tripStats(let decoded, _) = payload { self?.latestTripStats = decoded }
        }
        let altitudeService = AltitudeService(provider: locationProvider)
        altitudeService.start()
        services.append(altitudeService)
        subscribe(to: altitudeService.payloads) { [weak self] payload in
            if case .altitude(let decoded, _) = payload { self?.latestAltitude = decoded }
        }
    }

    private func startMotionServices(_ motionProvider: RealMotionProvider) {
        let leanService = LeanAngleService(provider: motionProvider)
        leanService.start()
        services.append(leanService)
        subscribe(to: leanService.encodedPayloads) { [weak self] payload in
            guard let self, case .leanAngle(var decoded, _) = payload else { return }
            if self.leanCalibrated {
                let raw = Double(decoded.currentLeanDegX10) / 10.0
                let adjusted = raw - self.leanReferenceAngle
                decoded.currentLeanDegX10 = Int16(max(-900, min(900, adjusted * 10)))
            }
            self.latestLeanAngle = decoded
        }
    }

    private func startClockService() {
        let clockService = ClockService(provider: SystemClockProvider())
        clockService.start()
        services.append(clockService)
        subscribe(to: clockService.encodedPayloads) { [weak self] payload in
            if case .clock(let decoded, _) = payload { self?.latestClock = decoded }
        }
    }

    private func startWeatherService() {
        guard let locationProvider else { return }
        #if canImport(WeatherKit)
        startWeatherService(
            client: WeatherKitClient(),
            locationProvider: locationProvider
        )
        #endif
    }

    /// Fetch weather using the given client and location provider.
    /// Retries up to 3 times on failure, with 30-second delays.
    func startWeatherService(
        client: some WeatherServiceClient,
        locationProvider: some LocationProvider
    ) {
        tasks.append(Task { @MainActor [weak self] in
            // Wait for a real location from the existing provider (up to 5s).
            let sample = await Self.firstSample(
                from: locationProvider, timeoutSeconds: 5
            )
            let lat = sample?.latitude ?? 47.56
            let lon = sample?.longitude ?? 7.59

            let maxAttempts = 3
            for attempt in 1...maxAttempts {
                guard self != nil else { return }
                do {
                    let response = try await client.fetchCurrentWeather(
                        latitude: lat, longitude: lon
                    )
                    self?.latestWeather = Self.weatherData(from: response)
                    return
                } catch {
                    if attempt < maxAttempts {
                        try? await Task.sleep(nanoseconds: 30_000_000_000)
                    } else {
                        self?.latestWeather = WeatherData(
                            condition: .cloudy,
                            temperatureCelsiusX10: 0,
                            highCelsiusX10: 0,
                            lowCelsiusX10: 0,
                            locationName: "Fehler"
                        )
                    }
                }
            }
        })
    }

    static func weatherData(from response: WeatherServiceResponse) -> WeatherData {
        let condition: WeatherConditionWire = {
            switch response.condition {
            case .clear: return .clear
            case .cloudy: return .cloudy
            case .rain: return .rain
            case .snow: return .snow
            case .fog: return .fog
            case .thunderstorm: return .thunderstorm
            }
        }()
        return WeatherData(
            condition: condition,
            temperatureCelsiusX10: Int16(response.temperatureCelsius * 10),
            highCelsiusX10: Int16(response.highCelsius * 10),
            lowCelsiusX10: Int16(response.lowCelsius * 10),
            locationName: response.locationName.isEmpty ? "Basel" : response.locationName
        )
    }

    private func startMusicService() {
        guard let clock = try? WallClock(speedMultiplier: 1) else { return }
        let nowPlayingProvider = RealNowPlayingProvider(
            client: MediaPlayerNowPlayingClient(),
            clock: clock
        )
        services.append(nowPlayingProvider)
        tasks.append(Task { await nowPlayingProvider.start() })
        let musicService = MusicService(provider: nowPlayingProvider)
        musicService.start()
        services.append(musicService)
        subscribe(to: musicService.encodedPayloads) { [weak self] payload in
            if case .music(let decoded, _) = payload { self?.latestMusic = decoded }
        }
    }

    private func startCalendarService() {
        #if canImport(EventKit)
        guard let clock = try? WallClock(speedMultiplier: 1) else { return }
        let calendarProvider = RealCalendarProvider(
            client: EventKitCalendarClient(),
            clock: clock
        )
        services.append(calendarProvider)
        tasks.append(Task { await calendarProvider.start() })
        let calendarService = CalendarService(provider: calendarProvider)
        calendarService.start()
        services.append(calendarService)
        subscribe(to: calendarService.encodedPayloads) { [weak self] payload in
            if case .appointment(let decoded, _) = payload { self?.latestAppointment = decoded }
        }
        #endif
    }

    private func startCallService() {
        let callObserver = RealCallObserver(client: CXCallObserverClient())
        let callService = CallAlertService(observer: callObserver)
        callService.start()
        services.append(callService)
        subscribe(to: callService.encodedPayloads) { [weak self] payload in
            if case .incomingCall(let decoded, _) = payload { self?.latestIncomingCall = decoded }
        }
    }

    private func startBlitzerService(locationProvider: RealLocationProvider) {
        guard let database = try? BundledSpeedCameraDatabase() else { return }
        let blitzerService = BlitzerAlertService(
            locationProvider: locationProvider,
            database: database
        )
        services.append(blitzerService)
        tasks.append(Task { [weak self] in
            await blitzerService.start()
            for await data in blitzerService.payloads {
                guard let self else { return }
                if let payload = try? ScreenPayloadCodec.decode(data),
                   case .blitzer(let decoded, _) = payload {
                    await MainActor.run { self.latestBlitzer = decoded }
                }
            }
        })
    }

    private func startFuelService(locationProvider: RealLocationProvider) {
        let fuelLog = FuelLog(store: DocumentsFuelLogStore())
        let tankLiters = UserDefaults.standard.double(forKey: "scramscreen.fuel.tankCapacityLiters")
        let capacityMl = (tankLiters > 0 ? tankLiters : 15.0) * 1000.0
        let fuelService = FuelService(
            provider: locationProvider,
            fuelLog: fuelLog,
            settings: FuelSettings(tankCapacityMl: capacityMl)
        )
        fuelService.start()
        services.append(fuelService)
        subscribe(to: fuelService.payloads) { [weak self] payload in
            if case .fuelEstimate(let decoded, _) = payload { self?.latestFuel = decoded }
        }
    }

    // MARK: - Stream subscription helper

    private func subscribe(
        to stream: AsyncStream<Data>,
        handler: @MainActor @escaping (ScreenPayload) -> Void
    ) {
        tasks.append(Task { @MainActor [weak self] in
            for await data in stream {
                guard self != nil else { return }
                if let payload = try? ScreenPayloadCodec.decode(data) {
                    handler(payload)
                }
            }
        })
    }

    // MARK: - Location helper

    /// Await the first sample from a location provider, returning nil if
    /// no sample arrives within `timeoutSeconds`.
    static func firstSample(
        from provider: some LocationProvider,
        timeoutSeconds: Int
    ) async -> LocationSample? {
        await withTaskGroup(of: LocationSample?.self) { group in
            group.addTask {
                var iterator = provider.samples.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(
                    nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000
                )
                return nil
            }
            // First child to finish wins; cancel the other.
            let result = await group.next().flatMap { $0 }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Service teardown

    // swiftlint:disable:next cyclomatic_complexity
    private func stopAllServices() {
        for service in services {
            switch service {
            case let svc as SpeedHeadingService: svc.stop()
            case let svc as CompassService: svc.stop()
            case let svc as TripStatsService: svc.stop()
            case let svc as LeanAngleService: svc.stop()
            case let svc as ClockService: svc.stop()
            case let svc as AltitudeService: svc.stop()
            case let svc as WeatherService: svc.stop()
            case let svc as MusicService: svc.stop()
            case let svc as CalendarService: svc.stop()
            case let svc as CallAlertService: svc.stop()
            case let svc as FuelService: svc.stop()
            case let svc as BlitzerAlertService:
                Task { await svc.stop() }
            default: break
            }
        }
    }
}
// swiftlint:enable type_body_length file_length
