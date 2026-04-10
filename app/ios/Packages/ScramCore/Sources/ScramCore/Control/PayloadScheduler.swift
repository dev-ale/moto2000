import Foundation
import BLEProtocol

/// Prioritises BLE payload delivery based on which screen is active.
///
/// Rules:
///   - **Active screen**: payloads forwarded immediately.
///   - **Alert screens** (``ScreenID/incomingCall``, ``ScreenID/blitzer``):
///     always forwarded immediately regardless of active screen.
///   - **Background screens**: throttled to at most one payload per
///     ``backgroundInterval`` per screen.
///   - **Screen change**: when the active screen changes, the latest cached
///     payload for the new screen is forwarded immediately.
///
/// The scheduler does not depend on ``BLECentralClient`` directly — it
/// accepts a `send` closure so tests can capture writes without BLE.
public actor PayloadScheduler {

    /// Screens that bypass throttling regardless of the active screen.
    public static let alertScreenIDs: Set<ScreenID> = [.incomingCall, .blitzer]

    /// Minimum interval between background payload sends for a single screen.
    public let backgroundInterval: TimeInterval

    /// The closure used to send bytes over BLE (or to a test sink).
    private let sendHandler: @Sendable (Data) async throws -> Void

    /// Latest payload cached per screen.
    public private(set) var latestPayload: [ScreenID: Data] = [:]

    /// Which screen the firmware is currently displaying.
    public private(set) var activeScreenID: ScreenID?

    /// Last time a background payload was forwarded for each screen.
    private var lastBackgroundSend: [ScreenID: ContinuousClock.Instant] = [:]

    /// Clock for throttling. Tests can supply a different value.
    private let clock: ContinuousClock

    /// Creates a scheduler.
    ///
    /// - Parameters:
    ///   - backgroundInterval: Throttle interval for non-active, non-alert
    ///     screens. Default is 5 seconds.
    ///   - clock: Clock used for throttling. Default is `ContinuousClock()`.
    ///   - send: Closure that delivers bytes. Typically wired to
    ///     `bleClient.send(_:)`.
    public init(
        backgroundInterval: TimeInterval = 5.0,
        clock: ContinuousClock = ContinuousClock(),
        send: @escaping @Sendable (Data) async throws -> Void
    ) {
        self.backgroundInterval = backgroundInterval
        self.clock = clock
        self.sendHandler = send
    }

    /// Enqueue a payload for a given screen.
    ///
    /// The scheduler decides whether to forward immediately or throttle
    /// based on the current active screen.
    public func enqueue(screenID: ScreenID, payload: Data) async {
        latestPayload[screenID] = payload

        // Alert screens always forward immediately.
        if Self.alertScreenIDs.contains(screenID) {
            try? await sendHandler(payload)
            return
        }

        // Active screen forwards immediately.
        if screenID == activeScreenID {
            try? await sendHandler(payload)
            return
        }

        // Background screen: throttle.
        let now = clock.now
        let interval = Duration.seconds(backgroundInterval)
        if let lastSend = lastBackgroundSend[screenID],
           now - lastSend < interval {
            // Throttled — payload is cached but not sent yet.
            return
        }
        lastBackgroundSend[screenID] = now
        try? await sendHandler(payload)
    }

    /// Notify the scheduler that the firmware switched to a new screen.
    ///
    /// If there is a cached payload for the new screen, it is forwarded
    /// immediately.
    public func setActiveScreen(_ screenID: ScreenID) async {
        let previousActive = activeScreenID
        activeScreenID = screenID
        guard screenID != previousActive else { return }
        if let cached = latestPayload[screenID] {
            try? await sendHandler(cached)
        }
    }
}
