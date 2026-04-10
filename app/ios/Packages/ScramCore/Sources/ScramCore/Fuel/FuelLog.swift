import Foundation

/// Manages the fill log with persistence through a ``FuelLogStore``.
///
/// Thread-safe: all mutations go through the actor. The actor loads
/// entries lazily on first access and saves after every mutation.
public actor FuelLog {
    private var entries: [FuelFillEntry] = []
    private let store: any FuelLogStore
    private var loaded = false

    public init(store: any FuelLogStore) {
        self.store = store
    }

    /// Ensure entries are loaded from the store. Idempotent.
    private func ensureLoaded() async throws {
        guard !loaded else { return }
        entries = try await store.load()
        loaded = true
    }

    /// All fill entries, sorted by date (oldest first).
    public func allEntries() async throws -> [FuelFillEntry] {
        try await ensureLoaded()
        return entries.sorted { $0.date < $1.date }
    }

    /// Add a fill entry and persist.
    public func addFill(_ entry: FuelFillEntry) async throws {
        try await ensureLoaded()
        entries.append(entry)
        try await store.save(entries)
    }

    /// Clear all entries and persist.
    public func clear() async throws {
        entries = []
        loaded = true
        try await store.save(entries)
    }

    /// Average consumption in mL/km, or nil if unknown.
    public func averageConsumptionMlPerKm() async throws -> Double? {
        let fills = try await allEntries()
        return FuelRangeCalculator.averageConsumptionMlPerKm(fills: fills)
    }

    /// Estimated remaining fuel in mL.
    public func estimatedRemainingMl(
        currentDistanceSinceLastFillKm: Double,
        settings: FuelSettings
    ) async throws -> Double? {
        let fills = try await allEntries()
        return FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: currentDistanceSinceLastFillKm,
            settings: settings
        ).remainingMl
    }

    /// Estimated range in km.
    public func estimatedRangeKm(
        currentDistanceSinceLastFillKm: Double,
        settings: FuelSettings
    ) async throws -> Double? {
        let fills = try await allEntries()
        return FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: currentDistanceSinceLastFillKm,
            settings: settings
        ).rangeKm
    }

    /// Tank percentage (0..100).
    public func tankPercent(
        currentDistanceSinceLastFillKm: Double,
        settings: FuelSettings
    ) async throws -> Double? {
        let fills = try await allEntries()
        return FuelRangeCalculator.estimate(
            fills: fills,
            currentDistanceSinceLastFillKm: currentDistanceSinceLastFillKm,
            settings: settings
        ).tankPercent
    }
}
