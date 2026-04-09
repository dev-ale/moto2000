import BLEProtocol
import Foundation

/// Per-screen cache of the last successfully received payload.
///
/// During BLE outages the renderer keeps drawing whatever this cache holds
/// while the reconnect FSM does its thing. Once the cached entry for a
/// screen gets older than ``stalenessThresholdSeconds``, callers should
/// start showing the stale indicator (matching the `STALE` flag in the wire
/// format, see `docs/ble-protocol.md`).
///
/// The cache is clock-agnostic: every mutation takes a timestamp, so tests
/// can drive it with ``RideSimulatorKit/VirtualClock`` and production uses
/// ``RideSimulatorKit/WallClock``.
public actor LastKnownPayloadCache {
    public struct Entry: Sendable, Equatable {
        public let body: Data
        public let receivedAt: Double

        public init(body: Data, receivedAt: Double) {
            self.body = body
            self.receivedAt = receivedAt
        }
    }

    /// How many seconds after receipt an entry counts as stale.
    public let stalenessThresholdSeconds: Double

    private var entries: [ScreenID: Entry] = [:]

    public init(stalenessThresholdSeconds: Double = 2.0) {
        self.stalenessThresholdSeconds = stalenessThresholdSeconds
    }

    /// Store `body` under `screen`, stamped with `now`. Overwrites any
    /// previous entry for the same screen.
    public func store(_ body: Data, for screen: ScreenID, at now: Double) {
        entries[screen] = Entry(body: body, receivedAt: now)
    }

    /// The cached entry for `screen`, or `nil` if nothing has been stored
    /// yet.
    public func entry(for screen: ScreenID) -> Entry? {
        entries[screen]
    }

    /// Whether the cached entry for `screen` is older than the staleness
    /// threshold, evaluated at `now`.
    ///
    /// Returns `true` for screens that have no entry at all — a "never
    /// seen" screen is effectively stale.
    public func isStale(for screen: ScreenID, at now: Double) -> Bool {
        guard let entry = entries[screen] else { return true }
        return (now - entry.receivedAt) > stalenessThresholdSeconds
    }

    /// All screens with a cached entry, unordered.
    public var cachedScreens: [ScreenID] {
        Array(entries.keys)
    }

    /// Drop the entry for `screen`. No-op if absent.
    public func remove(_ screen: ScreenID) {
        entries.removeValue(forKey: screen)
    }

    /// Empty the cache entirely (e.g. on a hard reset).
    public func clear() {
        entries.removeAll()
    }
}
