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

/// Debug-only session that creates real providers and services without BLE,
/// decodes each service's encoded payloads back to typed data, and publishes
/// them for the ``DisplayPreviewView`` to render live.
// swiftlint:disable:next type_body_length
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

        startLocationServices(locationProvider)
        startMotionServices(motionProvider)
        startClockService()
        startWeatherService()
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
        let navService = NavigationService(
            routeEngine: engine,
            locationProvider: locationProvider
        )
        services.append(navService)
        let dest = NavigationRoute.LocationCoordinate(
            latitude: latitude,
            longitude: longitude
        )
        tasks.append(Task { @MainActor [weak self] in
            try? await navService.start(destination: dest)
            for await data in navService.navDataPayloads {
                guard self != nil else { return }
                if let payload = try? ScreenPayloadCodec.decode(data),
                   case .navigation(let decoded, _) = payload {
                    self?.latestNav = decoded
                }
            }
        })
        #endif
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

        // Save trip if we have stats
        if let tripData = latestTripStats {
            let summary = TripSummary(
                id: UUID(),
                date: Date(),
                duration: TimeInterval(tripData.rideTimeSeconds),
                distanceKm: Double(tripData.distanceMeters) / 1000.0,
                avgSpeedKmh: Double(tripData.averageSpeedKmhX10) / 10.0,
                maxSpeedKmh: Double(tripData.maxSpeedKmhX10) / 10.0,
                elevationGainM: Double(tripData.ascentMeters)
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
        #if canImport(WeatherKit)
        // Direct fetch — bypass provider/service chain for reliability
        tasks.append(Task { @MainActor [weak self] in
            let client = WeatherKitClient()
            let lat = CLLocationManager().location?.coordinate.latitude ?? 47.56
            let lon = CLLocationManager().location?.coordinate.longitude ?? 7.59
            do {
                let response = try await client.fetchCurrentWeather(
                    latitude: lat, longitude: lon
                )
                // Manually build WeatherData from response
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
                self?.latestWeather = WeatherData(
                    condition: condition,
                    temperatureCelsiusX10: Int16(response.temperatureCelsius * 10),
                    highCelsiusX10: Int16(response.highCelsius * 10),
                    lowCelsiusX10: Int16(response.lowCelsius * 10),
                    locationName: response.locationName.isEmpty ? "Basel" : response.locationName
                )
            } catch {
                // Show error on the weather screen so user can see what's wrong
                self?.latestWeather = WeatherData(
                    condition: .cloudy,
                    temperatureCelsiusX10: 0,
                    highCelsiusX10: 0,
                    lowCelsiusX10: 0,
                    locationName: "Fehler"
                )
                print("WeatherKit error: \(error)")
            }
        })
        #endif
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
        let fuelService = FuelService(
            provider: locationProvider,
            fuelLog: fuelLog
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
