import Foundation
import BLEProtocol

/// Tiny abstraction over UserDefaults so the screen-preferences round-trip
/// can be tested with an in-memory fake instead of touching the real
/// defaults database.
public protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
}

/// In-memory implementation of ``KeyValueStore``. Useful for tests; not
/// shipped in the app target's persistence path.
public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func data(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func setData(_ data: Data?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        if let data { storage[key] = data } else { storage.removeValue(forKey: key) }
    }
}

extension UserDefaults: KeyValueStore {
    public func setData(_ data: Data?, forKey key: String) {
        if let data { set(data, forKey: key) } else { removeObject(forKey: key) }
    }
}

/// Persisted user preferences for the screen picker: the order of the
/// screens and which ones are enabled.
public struct ScreenPreferences: Codable, Equatable, Sendable {
    public var orderedScreenIDs: [UInt8]
    public var disabledScreenIDs: Set<UInt8>

    public init(orderedScreenIDs: [UInt8] = [], disabledScreenIDs: Set<UInt8> = []) {
        self.orderedScreenIDs = orderedScreenIDs
        self.disabledScreenIDs = disabledScreenIDs
    }

    public static let storageKey = "scramscreen.screenPreferences.v1"

    public func save(to store: any KeyValueStore) throws {
        let data = try JSONEncoder().encode(self)
        store.setData(data, forKey: Self.storageKey)
    }

    public static func load(from store: any KeyValueStore) -> ScreenPreferences? {
        guard let data = store.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(ScreenPreferences.self, from: data)
    }

    /// Apply the preferences to the canonical list, returning the user's
    /// ordering with the enabled flag preserved.
    public func apply(to base: [ScreenSelection]) -> [ScreenSelection] {
        var byID: [UInt8: ScreenSelection] = [:]
        for s in base { byID[s.screenID.rawValue] = s }
        var result: [ScreenSelection] = []
        // First emit anything in the persisted order, in order.
        for id in orderedScreenIDs {
            if var s = byID.removeValue(forKey: id) {
                s.isEnabled = !disabledScreenIDs.contains(id)
                result.append(s)
            }
        }
        // Then append any leftover screens (e.g. new screens added after
        // the user persisted preferences) in their natural order.
        for s in base where byID[s.screenID.rawValue] != nil {
            var copy = s
            copy.isEnabled = !disabledScreenIDs.contains(s.screenID.rawValue)
            result.append(copy)
        }
        return result
    }
}
