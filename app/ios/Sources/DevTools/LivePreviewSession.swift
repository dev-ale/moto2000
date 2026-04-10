#if DEBUG
import BLEProtocol
import Foundation
import Observation
import RideSimulatorKit
import ScramCore

/// Debug-only session that creates real providers and services without BLE,
/// decodes each service's encoded payloads back to typed data, and publishes
/// them for the ``DisplayPreviewView`` to render live.
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

    /// The ordered list of screens the user can swipe through.
    let availableScreens: [ScreenID] = [
        .speedHeading,
        .compass,
        .tripStats,
        .leanAngle,
        .clock,
        .altitude,
        .weather,
        .music,
        .fuelEstimate,
        .navigation,
        .appointment,
        .incomingCall,
        .blitzer
    ]

    // MARK: - Internal state

    private var services: [Any] = []
    private var tasks: [Task<Void, Never>] = []
    private var isRunning = false

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let locationProvider = RealLocationProvider()
        let motionProvider = RealMotionProvider()
        startLocationServices(locationProvider)
        startMotionServices(motionProvider)
        startClockService()
        startWeatherService()
        startMusicService()
        startCalendarService()
        startCallService()
        startBlitzerService(locationProvider: locationProvider)
        startFuelService(locationProvider: locationProvider)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

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
            if case .leanAngle(let decoded, _) = payload { self?.latestLeanAngle = decoded }
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
        guard let clock = try? WallClock(speedMultiplier: 1) else { return }
        let weatherProvider = RealWeatherProvider(
            client: WeatherKitClient(),
            clock: clock,
            coordinate: .init(latitude: 0, longitude: 0)
        )
        let weatherService = WeatherService(provider: weatherProvider)
        weatherService.start()
        services.append(weatherService)
        subscribe(to: weatherService.encodedPayloads) { [weak self] payload in
            if case .weather(let decoded, _) = payload { self?.latestWeather = decoded }
        }
        #endif
    }

    private func startMusicService() {
        guard let clock = try? WallClock(speedMultiplier: 1) else { return }
        let nowPlayingProvider = RealNowPlayingProvider(
            client: MediaPlayerNowPlayingClient(),
            clock: clock
        )
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
        tasks.append(Task { [weak self] in
            for await data in stream {
                guard self != nil else { return }
                if let payload = try? ScreenPayloadCodec.decode(data) {
                    await MainActor.run { handler(payload) }
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
#endif
