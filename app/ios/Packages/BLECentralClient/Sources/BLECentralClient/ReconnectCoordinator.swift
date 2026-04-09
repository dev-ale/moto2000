import BLEProtocol
import Foundation
import RideSimulatorKit

/// Glue that drives a ``BLECentralClient`` through a
/// ``ReconnectStateMachine`` using a ``SimulatedClock`` for timing.
///
/// The coordinator is the component the app actually wires together. In
/// tests, inject a ``TestBLECentralClient`` and a
/// ``RideSimulatorKit/VirtualClock``; in production, inject
/// ``CoreBluetoothCentralClient`` and ``RideSimulatorKit/WallClock``.
///
/// The coordinator translates FSM ``ReconnectAction`` values into
/// concrete client calls and clock sleeps, and pumps client state changes
/// back into the FSM as events. It also keeps the ``LastKnownPayloadCache``
/// and ``ConnectionHealthMonitor`` fresh on every successful write.
public actor ReconnectCoordinator {
    public let client: any BLECentralClient
    public let fsm: ReconnectStateMachine
    public let cache: LastKnownPayloadCache
    public let health: ConnectionHealthMonitor
    private let clock: any SimulatedClock

    /// Seconds elapsed between the most recent `didDisconnect` and the
    /// most recent `didConnect`. `nil` until a full cycle is observed.
    /// Tests assert on this against the 5 s target.
    public private(set) var lastReconnectLatencySeconds: Double?

    private var lastDisconnectAt: Double?

    public init(
        client: any BLECentralClient,
        clock: any SimulatedClock,
        fsm: ReconnectStateMachine = ReconnectStateMachine(),
        cache: LastKnownPayloadCache = LastKnownPayloadCache(),
        health: ConnectionHealthMonitor = ConnectionHealthMonitor()
    ) {
        self.client = client
        self.clock = clock
        self.fsm = fsm
        self.cache = cache
        self.health = health
    }

    /// Send `body` for `screen`, updating the cache on success. Silently
    /// caches on failure so the renderer still has something to draw.
    public func send(body: Data, for screen: ScreenID) async {
        let now = await clock.nowSeconds
        do {
            try await client.send(body)
            await cache.store(body, for: screen, at: now)
            await health.recordSuccessfulWrite(at: now)
        } catch {
            // Swallow — the link is down and the FSM is already handling
            // reconnect. We keep whatever is in the cache.
        }
    }

    /// Feed an external event into the FSM and execute the resulting
    /// action. Timer-driven actions are scheduled via the clock and loop
    /// back in as `reconnectTick`s.
    public func handle(_ event: ReconnectEvent) async {
        let action = await fsm.handle(event)
        await health.updateState(await fsm.state)

        switch event {
        case .didDisconnect:
            lastDisconnectAt = await clock.nowSeconds
        case .didConnect:
            if let dropped = lastDisconnectAt {
                let now = await clock.nowSeconds
                lastReconnectLatencySeconds = now - dropped
                lastDisconnectAt = nil
            }
        default:
            break
        }

        await execute(action)
    }

    private func execute(_ action: ReconnectAction) async {
        switch action {
        case .none, .cancelAll:
            return
        case .startScan, .attemptConnect:
            await client.connect()
        case .scheduleNextAttempt(let delay):
            let wake = await clock.nowSeconds + delay
            Task { [weak self] in
                guard let self else { return }
                try? await self.clock.sleep(until: wake)
                await self.handle(.reconnectTick)
            }
        }
    }
}
