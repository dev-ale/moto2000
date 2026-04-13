import Foundation
import BLEProtocol
import BLECentralClient
import RideSimulatorKit

/// Dependencies that a ``RideSession`` needs to create services.
///
/// Callers populate only the providers they have available; services for
/// missing providers are skipped. This avoids requiring every provider
/// at init time and lets the session adapt to what the app can supply.
public struct RideSessionDependencies: Sendable {
    public var locationProvider: (any LocationProvider)?
    public var motionProvider: (any MotionProvider)?
    public var weatherProvider: (any WeatherProvider)?
    public var nowPlayingProvider: (any NowPlayingProvider)?
    public var calendarProvider: (any CalendarProvider)?
    public var callObserver: (any CallObserver)?
    public var speedCameraDatabase: (any SpeedCameraDatabase)?
    public var fuelLog: FuelLog?
    public var fuelSettings: FuelSettings

    public init(
        locationProvider: (any LocationProvider)? = nil,
        motionProvider: (any MotionProvider)? = nil,
        weatherProvider: (any WeatherProvider)? = nil,
        nowPlayingProvider: (any NowPlayingProvider)? = nil,
        calendarProvider: (any CalendarProvider)? = nil,
        callObserver: (any CallObserver)? = nil,
        speedCameraDatabase: (any SpeedCameraDatabase)? = nil,
        fuelLog: FuelLog? = nil,
        fuelSettings: FuelSettings = FuelSettings()
    ) {
        self.locationProvider = locationProvider
        self.motionProvider = motionProvider
        self.weatherProvider = weatherProvider
        self.nowPlayingProvider = nowPlayingProvider
        self.calendarProvider = calendarProvider
        self.callObserver = callObserver
        self.speedCameraDatabase = speedCameraDatabase
        self.fuelLog = fuelLog
        self.fuelSettings = fuelSettings
    }
}

/// Central orchestration layer for an active ride.
///
/// A ``RideSession`` ties together all data services, the
/// ``PayloadScheduler``, and the BLE connection for the duration of a
/// ride. It is the single place that:
///
///   1. Sends the ``ScreenOrderCommand`` on connect.
///   2. Creates and starts every enabled service.
///   3. Routes each service's output through the ``PayloadScheduler``.
///   4. Listens for `SCREEN_CHANGED` status notifications.
///   5. Saves trip data on stop.
///
/// Lifecycle: create one per BLE connection, call ``start()``, and call
/// ``stop()`` when the ride ends (or the link drops).
public actor RideSession {

    // MARK: - Dependencies

    private let bleClient: any BLECentralClient
    private let preferences: ScreenPreferences
    private let deps: RideSessionDependencies

    // MARK: - Internal state

    private var scheduler: PayloadScheduler?
    private var serviceTasks: [Task<Void, Never>] = []
    private var statusListenerTask: Task<Void, Never>?

    // Active services for the session duration.
    private var activeServices: [any PayloadService] = []

    // Typed reference for queryable state (TripStatsService.currentSnapshot).
    private var tripStatsService: TripStatsService?

    /// Whether the session is currently running.
    public private(set) var isRunning = false

    /// The enabled screen IDs sent to the firmware.
    public private(set) var enabledScreenIDs: [ScreenID] = []

    /// Creates a ride session.
    ///
    /// - Parameters:
    ///   - bleClient: The BLE transport to write payloads to.
    ///   - preferences: Screen ordering and enablement preferences.
    ///   - dependencies: Provider dependencies for data services.
    public init(
        bleClient: any BLECentralClient,
        preferences: ScreenPreferences,
        dependencies: RideSessionDependencies
    ) {
        self.bleClient = bleClient
        self.preferences = preferences
        self.deps = dependencies
    }

    // MARK: - Public API

    /// Start the ride session.
    ///
    /// This sends the screen order, creates all services with available
    /// providers, and begins routing payloads to BLE.
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        // 1. Compute the enabled screen order from preferences.
        let selections = preferences.apply(to: ScreenSelection.availableScreens)
        enabledScreenIDs = selections
            .filter(\.isEnabled)
            .map(\.screenID)

        // 2. Send screen order command to firmware.
        let orderCmd = ScreenOrderCommand(screenIDs: enabledScreenIDs)
        let orderData = try orderCmd.encode()
        try await bleClient.send(orderData)

        // 3. Create the scheduler.
        let sched = PayloadScheduler()
        self.scheduler = sched

        // Set the first screen as active.
        if let firstScreen = enabledScreenIDs.first {
            sched.activeScreen = firstScreen
        }

        // 4. Create and start services, subscribing to their output.
        await createAndStartServices(scheduler: sched)

        // 5. Listen for SCREEN_CHANGED status notifications.
        let statusStream = bleClient.statusStream
        statusListenerTask = Task { [weak self] in
            for await data in statusStream {
                guard let self, !Task.isCancelled else { return }
                await self.handleStatusNotification(data)
            }
        }
    }

    /// Stop the ride session and clean up.
    ///
    /// Cancels all service tasks and saves trip data.
    public func stop() async {
        guard isRunning else { return }
        isRunning = false

        // Cancel status listener.
        statusListenerTask?.cancel()
        statusListenerTask = nil

        // Cancel all service forwarding tasks.
        for task in serviceTasks {
            task.cancel()
        }
        serviceTasks.removeAll()

        // Stop all services.
        for service in activeServices {
            await service.stop()
        }
        activeServices.removeAll()
        tripStatsService = nil
        scheduler = nil
    }

    /// The current trip stats snapshot, if the trip stats service is running.
    public var tripSnapshot: TripStatsData? {
        tripStatsService?.currentSnapshot
    }

    // MARK: - Private

    private func createAndStartServices(scheduler: PayloadScheduler) async {
        for registration in ServiceRegistry.all {
            guard let service = registration.factory(deps) else { continue }

            // Capture typed references for queryable services.
            if let trip = service as? TripStatsService {
                tripStatsService = trip
            }

            await service.start()
            activeServices.append(service)

            let stream = service.payloadStream
            let task = Task { [weak self] in
                for await payload in stream {
                    guard self != nil, !Task.isCancelled else { return }
                    await self?.scheduleAndSend(payload)
                }
            }
            serviceTasks.append(task)
        }
    }

    private func handleStatusNotification(_ data: Data) async {
        guard let message = try? StatusMessage.decode(data) else { return }
        switch message {
        case .screenChanged(let screenID):
            scheduler?.activeScreen = screenID
        case .firmwareVersion(let maj, let min, let pat):
            // Surface to the iOS UI layer via NotificationCenter so the
            // More tab can show it. RideSession is the only consumer
            // of the BLE status stream (single-consumer AsyncStream).
            NotificationCenter.default.post(
                name: Notification.Name("scramFirmwareVersion"),
                object: nil,
                userInfo: ["major": maj, "minor": min, "patch": pat]
            )
        }
    }

    /// Route a payload through the scheduler and send results over BLE.
    private func scheduleAndSend(_ payload: Data) async {
        guard let scheduler else { return }
        let outgoing = scheduler.schedule(payload)
        for data in outgoing {
            try? await bleClient.send(data)
        }
    }
}
