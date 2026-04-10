import Foundation

/// Persisted user preferences for which EventKit calendars are included
/// when fetching appointments for the display.
///
/// Calendars default to **enabled**. Only explicitly disabled calendar
/// identifiers are persisted. This means newly-added calendars
/// automatically appear enabled, and removed calendars are cleaned up
/// on each ``reconcile(knownCalendarIDs:)`` call.
public final class CalendarPreferences: @unchecked Sendable {
    public static let storageKey = "scramscreen.calendarPreferences.v1"

    private let store: any KeyValueStore
    private let lock = NSLock()
    private var disabledIDs: Set<String>

    public init(store: any KeyValueStore) {
        self.store = store
        self.disabledIDs = Self.loadDisabledIDs(from: store)
    }

    // MARK: - Public API

    /// Returns `true` when the calendar with the given identifier is
    /// selected (i.e. its events should be shown).
    public func isSelected(_ calendarIdentifier: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !disabledIDs.contains(calendarIdentifier)
    }

    /// Toggles the selection state of a calendar.
    public func toggleSelection(_ calendarIdentifier: String) {
        lock.lock()
        if disabledIDs.contains(calendarIdentifier) {
            disabledIDs.remove(calendarIdentifier)
        } else {
            disabledIDs.insert(calendarIdentifier)
        }
        let snapshot = disabledIDs
        lock.unlock()
        persist(snapshot)
    }

    /// Explicitly sets whether a calendar is selected.
    public func setSelected(_ calendarIdentifier: String, enabled: Bool) {
        lock.lock()
        if enabled {
            disabledIDs.remove(calendarIdentifier)
        } else {
            disabledIDs.insert(calendarIdentifier)
        }
        let snapshot = disabledIDs
        lock.unlock()
        persist(snapshot)
    }

    /// Returns the current set of disabled calendar identifiers.
    public var disabledCalendarIDs: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return disabledIDs
    }

    /// Removes persisted state for calendars that no longer exist and
    /// ensures new calendars default to enabled.
    ///
    /// Call this whenever the system calendar list is refreshed so stale
    /// identifiers do not accumulate.
    public func reconcile(knownCalendarIDs: Set<String>) {
        lock.lock()
        disabledIDs = disabledIDs.intersection(knownCalendarIDs)
        let snapshot = disabledIDs
        lock.unlock()
        persist(snapshot)
    }

    // MARK: - Persistence

    private func persist(_ ids: Set<String>) {
        let sorted = ids.sorted()
        if let data = try? JSONEncoder().encode(sorted) {
            store.setData(data, forKey: Self.storageKey)
        }
    }

    private static func loadDisabledIDs(from store: any KeyValueStore) -> Set<String> {
        guard let data = store.data(forKey: storageKey) else { return [] }
        guard let array = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(array)
    }
}
