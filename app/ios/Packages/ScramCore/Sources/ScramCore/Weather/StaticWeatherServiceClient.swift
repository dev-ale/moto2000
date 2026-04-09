import Foundation
import RideSimulatorKit

/// Test-only ``WeatherServiceClient`` that returns a scripted response on
/// every call. Used by the Slice 7 test suite and by the dev-build UI when
/// running against a scenario file.
///
/// The response can be swapped at runtime via ``setResponse(_:)`` so tests
/// can simulate the upstream changing between refreshes.
public final class StaticWeatherServiceClient: WeatherServiceClient, @unchecked Sendable {
    private let lock = NSLock()
    private var currentResponse: WeatherServiceResponse
    private var fetchCount: Int = 0

    public init(response: WeatherServiceResponse) {
        self.currentResponse = response
    }

    public var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return fetchCount
    }

    public func setResponse(_ response: WeatherServiceResponse) {
        lock.lock()
        currentResponse = response
        lock.unlock()
    }

    public func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherServiceResponse {
        return readAndIncrement()
    }

    private func readAndIncrement() -> WeatherServiceResponse {
        lock.lock()
        fetchCount += 1
        let response = currentResponse
        lock.unlock()
        return response
    }
}
