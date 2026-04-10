import BLECentralClient
import BLEProtocol
import Foundation
import Observation
import RideSimulatorKit
import ScramCore

/// Bridges BLE connection events to ``RideSession`` lifecycle.
///
/// When the BLE link comes up the coordinator creates real providers,
/// builds ``RideSessionDependencies``, starts a ``RideSession``, and
/// begins streaming data to the ESP32. When the link drops (or the
/// user disconnects) it stops the session and persists the trip summary
/// through ``TripHistoryStore``.
///
/// The debug scenario picker is unaffected — it drives its own
/// ``ScenarioPlayer`` and never touches this coordinator.
@Observable
@MainActor
final class RideSessionCoordinator {

    // MARK: - Public state

    /// Whether a ride session is currently active.
    private(set) var isSessionActive = false

    // MARK: - Dependencies (injected once)

    private let bleClient: any BLECentralClient
    private let tripHistoryStore: TripHistoryStore
    private let fuelLogStore: any FuelLogStore
    private let screenPreferences: ScreenPreferences

    // MARK: - Session state (created per ride)

    private var rideSession: RideSession?
    private var observeTask: Task<Void, Never>?

    // MARK: - Init

    init(
        bleClient: any BLECentralClient,
        tripHistoryStore: TripHistoryStore = TripHistoryStore(),
        fuelLogStore: any FuelLogStore = DocumentsFuelLogStore(),
        screenPreferences: ScreenPreferences? = nil
    ) {
        self.bleClient = bleClient
        self.tripHistoryStore = tripHistoryStore
        self.fuelLogStore = fuelLogStore
        self.screenPreferences = screenPreferences
            ?? ScreenPreferences.load(from: UserDefaults.standard)
            ?? ScreenPreferences()
    }

    // MARK: - Observation

    /// Start observing BLE state changes. Call once from the app lifecycle.
    func startObserving() {
        guard observeTask == nil else { return }
        observeTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.bleClient.stateStream {
                guard !Task.isCancelled else { break }
                switch state {
                case .connected:
                    await self.handleConnect()
                case .disconnected:
                    await self.handleDisconnect()
                default:
                    break
                }
            }
        }
    }

    /// Stop observing and tear down any active session.
    func stopObserving() {
        observeTask?.cancel()
        observeTask = nil
        Task { await handleDisconnect() }
    }

    // MARK: - Session lifecycle

    private func handleConnect() async {
        // Don't create a second session if one is already running.
        guard rideSession == nil else { return }

        let deps = buildRealDependencies()
        let session = RideSession(
            bleClient: bleClient,
            preferences: screenPreferences,
            dependencies: deps
        )
        rideSession = session

        do {
            try await session.start()
            isSessionActive = true
        } catch {
            NSLog("RideSessionCoordinator: failed to start session: \(error)")
            rideSession = nil
            isSessionActive = false
        }
    }

    private func handleDisconnect() async {
        guard let session = rideSession else { return }

        // Grab the trip snapshot before stopping (stop nils out the service).
        let snapshot = await session.tripSnapshot

        await session.stop()
        rideSession = nil
        isSessionActive = false

        // Persist trip summary if we have meaningful data.
        if let data = snapshot {
            saveTripSummary(from: data)
        }
    }

    // MARK: - Provider factory

    private func buildRealDependencies() -> RideSessionDependencies {
        let locationProvider = RealLocationProvider()
        let motionProvider = RealMotionProvider()

        let clock = try? WallClock(speedMultiplier: 1)

        // Weather provider — uses the stub WeatherKitClient until the
        // real integration lands. RealWeatherProvider swallows the
        // .notImplemented error and simply never emits snapshots.
        var weatherProvider: (any WeatherProvider)?
        #if canImport(WeatherKit)
        weatherProvider = clock.map { clk in
            RealWeatherProvider(
                client: WeatherKitClient(),
                clock: clk,
                coordinate: .init(latitude: 0, longitude: 0)
            )
        }
        #endif

        // Music — MediaPlayerNowPlayingClient is a stub for now.
        let nowPlayingProvider: RealNowPlayingProvider? = clock.map { clk in
            RealNowPlayingProvider(
                client: MediaPlayerNowPlayingClient(),
                clock: clk
            )
        }

        // Calendar — EventKitCalendarClient is a stub for now.
        var calendarProvider: (any CalendarProvider)?
        #if canImport(EventKit)
        calendarProvider = clock.map { clk in
            RealCalendarProvider(
                client: EventKitCalendarClient(),
                clock: clk
            )
        }
        #endif

        // Calls — CXCallObserverClient is a stub for now.
        let callObserver = RealCallObserver(client: CXCallObserverClient())

        // Speed cameras — loaded from the bundled SQLite database.
        var speedCameraDB: BundledSpeedCameraDatabase?
        do {
            speedCameraDB = try BundledSpeedCameraDatabase()
        } catch {
            NSLog("RideSessionCoordinator: speed camera database unavailable: \(error)")
        }

        // Fuel log — backed by the documents-directory store.
        let fuelLog = FuelLog(store: fuelLogStore)

        return RideSessionDependencies(
            locationProvider: locationProvider,
            motionProvider: motionProvider,
            weatherProvider: weatherProvider,
            nowPlayingProvider: nowPlayingProvider,
            calendarProvider: calendarProvider,
            callObserver: callObserver,
            speedCameraDatabase: speedCameraDB,
            fuelLog: fuelLog
        )
    }

    // MARK: - Trip persistence

    private func saveTripSummary(from data: TripStatsData) {
        // Only persist trips with meaningful distance (> 100 m).
        guard data.distanceMeters > 100 else { return }

        let summary = TripSummary(
            duration: TimeInterval(data.rideTimeSeconds),
            distanceKm: Double(data.distanceMeters) / 1000.0,
            avgSpeedKmh: Double(data.averageSpeedKmhX10) / 10.0,
            maxSpeedKmh: Double(data.maxSpeedKmhX10) / 10.0,
            elevationGainM: Double(data.ascentMeters)
        )
        tripHistoryStore.save(summary)
    }
}
