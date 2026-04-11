import Foundation

/// Persistence layer for maintenance log entries. Stores ``MaintenanceEntry``
/// values as a JSON array in `UserDefaults`.
///
/// All returned arrays are sorted by date descending (newest first).
public final class MaintenanceStore: Sendable {
    private static let defaultsKey = "scramscreen.maintenanceLog"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Appends a maintenance entry to the persisted log.
    public func save(_ entry: MaintenanceEntry) {
        var all = loadAll()
        all.append(entry)
        persist(all)
    }

    /// Returns all persisted maintenance entries, newest first.
    public func loadAll() -> [MaintenanceEntry] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([MaintenanceEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.date > $1.date }
    }

    /// Removes all persisted maintenance entries.
    public func deleteAll() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    // MARK: - Private

    private func persist(_ entries: [MaintenanceEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
