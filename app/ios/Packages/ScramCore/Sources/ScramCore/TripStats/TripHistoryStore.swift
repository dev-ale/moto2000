import Foundation

/// Persistence layer for ride history. Stores ``TripSummary`` values as a
/// JSON array in `UserDefaults`.
///
/// All returned arrays are sorted by date descending (newest first).
public final class TripHistoryStore: Sendable {
    private static let defaultsKey = "scramscreen.tripHistory"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Appends a trip summary to the persisted history.
    public func save(_ summary: TripSummary) {
        var all = loadAll()
        all.append(summary)
        persist(all)
    }

    /// Returns all persisted trip summaries, newest first.
    public func loadAll() -> [TripSummary] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let summaries = try? decoder.decode([TripSummary].self, from: data) else {
            return []
        }
        return summaries.sorted { $0.date > $1.date }
    }

    /// Removes all persisted trip summaries.
    public func deleteAll() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    // MARK: - Private

    private func persist(_ summaries: [TripSummary]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(summaries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
