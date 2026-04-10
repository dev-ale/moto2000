import Foundation

/// Abstraction for persisting the fuel fill log.
///
/// The real implementation writes JSON to the app's documents directory.
/// Tests use an in-memory implementation that never touches the filesystem.
public protocol FuelLogStore: Sendable {
    func load() async throws -> [FuelFillEntry]
    func save(_ entries: [FuelFillEntry]) async throws
}

/// In-memory implementation for tests. Thread-safe via actor isolation.
public actor InMemoryFuelLogStore: FuelLogStore {
    private var entries: [FuelFillEntry] = []

    public init(entries: [FuelFillEntry] = []) {
        self.entries = entries
    }

    public func load() async throws -> [FuelFillEntry] {
        entries
    }

    public func save(_ entries: [FuelFillEntry]) async throws {
        self.entries = entries
    }
}

/// Persists fuel fill entries as JSON in the app's documents directory.
public actor DocumentsFuelLogStore: FuelLogStore {
    private let fileURL: URL

    public init(filename: String = "fuel_fill_log.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent(filename)
    }

    public func load() async throws -> [FuelFillEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([FuelFillEntry].self, from: data)
    }

    public func save(_ entries: [FuelFillEntry]) async throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
