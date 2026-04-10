import Foundation
import BLEProtocol
import RideSimulatorKit

/// Combines location, ambient light, and time to drive the brightness
/// policy and emit ``ControlCommand`` values.
///
/// The service re-evaluates every 60 seconds (configurable for tests) and
/// whenever a new ambient light sample arrives.
///
/// Downstream consumers read:
/// - ``commands``: encoded ``ControlCommand.setBrightness`` payloads.
/// - ``isNightMode``: the current night-mode flag for other services to
///   set on their ``ScreenFlags``.
///
/// ## What's deferred (needs hardware)
///
/// - ESP32 PWM brightness control (`ledc` driver) — the command is sent
///   over BLE but the firmware does not yet act on it.
/// - LVGL palette swap on real firmware — the host-sim already renders
///   night mode via the `NIGHT_MODE` flag.
/// - Real `AmbientLightProvider` — see ``SystemAmbientLightProvider``.
public actor NightModeService {

    // MARK: - Public state

    /// Whether night mode is currently active. Other services read this
    /// to set ``ScreenFlags.nightMode`` on their payloads.
    public private(set) var isNightMode: Bool = false

    /// The most recent brightness decision.
    public private(set) var lastDecision: BrightnessDecision?

    /// Stream of encoded ``ControlCommand`` data ready to write to BLE.
    public nonisolated let commands: AsyncStream<Data>

    // MARK: - Dependencies

    private let locationProvider: any LocationProvider
    private let ambientLightProvider: (any AmbientLightProvider)?
    private let dateProvider: @Sendable () -> Date
    private let evaluationInterval: TimeInterval

    // MARK: - Internal state

    private let continuation: AsyncStream<Data>.Continuation
    private var latitude: Double = 47.56  // Basel default
    private var longitude: Double = 7.59
    private var timeZoneOffset: Int = 1   // CET default
    private var latestLux: Double?
    private var userOverride: BrightnessOverride?
    private var evaluationTask: Task<Void, Never>?
    private var lightTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?

    /// Create a night mode service.
    ///
    /// - Parameters:
    ///   - locationProvider: Source of GPS coordinates for sunrise/sunset.
    ///   - ambientLightProvider: Optional ambient light sensor. Pass `nil`
    ///     to use time-based decisions only.
    ///   - dateProvider: Returns the current time. Inject a closure over
    ///     a ``VirtualClock`` for tests.
    ///   - evaluationInterval: Seconds between periodic re-evaluations.
    ///     Default is 60s; tests use shorter intervals.
    ///   - timeZoneOffset: Hours east of UTC. Default is 1 (CET).
    public init(
        locationProvider: any LocationProvider,
        ambientLightProvider: (any AmbientLightProvider)? = nil,
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        evaluationInterval: TimeInterval = 60,
        timeZoneOffset: Int = 1
    ) {
        self.locationProvider = locationProvider
        self.ambientLightProvider = ambientLightProvider
        self.dateProvider = dateProvider
        self.evaluationInterval = evaluationInterval
        self.timeZoneOffset = timeZoneOffset

        var cont: AsyncStream<Data>.Continuation!
        self.commands = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    deinit {
        evaluationTask?.cancel()
        lightTask?.cancel()
        locationTask?.cancel()
        continuation.finish()
    }

    // MARK: - Public API

    /// Start the periodic evaluation loop and begin consuming provider
    /// streams.
    public func start() {
        guard evaluationTask == nil else { return }

        // Track location for sunrise/sunset.
        let locStream = locationProvider.samples
        locationTask = Task { [weak self] in
            for await sample in locStream {
                guard let self, !Task.isCancelled else { return }
                await self.updateLocation(sample)
            }
        }

        // Track ambient light.
        if let lightProvider = ambientLightProvider {
            let lightStream = lightProvider.samples
            lightTask = Task { [weak self] in
                for await sample in lightStream {
                    guard let self, !Task.isCancelled else { return }
                    await self.updateLux(sample.lux)
                }
            }
        }

        // Periodic re-evaluation.
        evaluationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.evaluate()
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.evaluationInterval * 1_000_000_000))
                } catch {
                    return // Cancelled.
                }
            }
        }
    }

    /// Stop all evaluation and finish the command stream.
    public func stop() {
        evaluationTask?.cancel()
        evaluationTask = nil
        lightTask?.cancel()
        lightTask = nil
        locationTask?.cancel()
        locationTask = nil
        continuation.finish()
    }

    /// Set a user override. Takes effect immediately.
    public func setUserOverride(_ override: BrightnessOverride?) {
        self.userOverride = override
        evaluate()
    }

    /// Update the time zone offset (hours east of UTC).
    public func setTimeZoneOffset(_ offset: Int) {
        self.timeZoneOffset = offset
    }

    // MARK: - Internal

    private func updateLocation(_ sample: LocationSample) {
        latitude = sample.latitude
        longitude = sample.longitude
    }

    private func updateLux(_ lux: Double) {
        latestLux = lux
        evaluate()
    }

    /// Run the brightness policy and emit a command if the decision changed.
    @discardableResult
    func evaluate() -> BrightnessDecision {
        let now = dateProvider()
        let sunTimes = SunriseSunsetCalculator.calculate(
            latitude: latitude,
            longitude: longitude,
            date: now,
            timeZoneOffset: timeZoneOffset
        )

        let decision = BrightnessPolicy.decide(
            currentTime: now,
            sunTimes: sunTimes,
            ambientLux: latestLux,
            userOverride: userOverride
        )

        let changed = decision != lastDecision
        lastDecision = decision
        isNightMode = decision.nightMode

        if changed {
            let command = ControlCommand.setBrightness(decision.brightnessPercent)
            continuation.yield(command.encode())
        }

        return decision
    }
}
