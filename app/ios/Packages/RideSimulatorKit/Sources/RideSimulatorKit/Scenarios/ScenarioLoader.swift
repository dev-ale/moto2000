import Foundation

/// Reads and writes ``Scenario`` values from JSON files.
public enum ScenarioLoader {
    public static func load(from url: URL) throws -> Scenario {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ScenarioError.fileNotFound(url.path)
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> Scenario {
        let decoder = JSONDecoder()
        let scenario: Scenario
        do {
            scenario = try decoder.decode(Scenario.self, from: data)
        } catch {
            throw ScenarioError.decodeFailure(String(describing: error))
        }
        guard scenario.version == Scenario.currentVersion else {
            throw ScenarioError.unsupportedVersion(scenario.version)
        }
        return scenario
    }

    public static func encode(_ scenario: Scenario) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(scenario)
    }

    public static func save(_ scenario: Scenario, to url: URL) throws {
        let data = try encode(scenario)
        try data.write(to: url, options: .atomic)
    }
}
