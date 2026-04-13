import Foundation
import RideSimulatorKit

/// Abstraction over "where does a current-weather snapshot come from".
///
/// Slice 7 injects either the test-only ``StaticWeatherServiceClient`` or
/// the ``WeatherKitClient`` stub. A follow-up slice will provide a real
/// WeatherKit REST client implementation; see ``WeatherKitClient`` for why
/// the integration is deferred.
public protocol WeatherServiceClient: Sendable {
    /// Fetch the current weather for a latitude/longitude coordinate.
    ///
    /// The response is the raw weather model — mapping to a
    /// ``WeatherSnapshot`` (the `WeatherProvider` stream element) is the
    /// responsibility of the caller so a single client can feed multiple
    /// downstream transformers.
    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherServiceResponse
}

/// Raw response from a ``WeatherServiceClient``.
///
/// The shape intentionally mirrors ``WeatherSnapshot`` minus the scenario
/// time, so a ``RealWeatherProvider`` can stamp its own clock value when it
/// emits downstream.
public struct WeatherServiceResponse: Sendable, Equatable {
    public var condition: WeatherCondition
    public var temperatureCelsius: Double
    public var highCelsius: Double
    public var lowCelsius: Double
    public var locationName: String
    /// Minutes until next precipitation, or nil if none expected.
    public var precipMinutesUntil: Int?

    public init(
        condition: WeatherCondition,
        temperatureCelsius: Double,
        highCelsius: Double,
        lowCelsius: Double,
        locationName: String,
        precipMinutesUntil: Int? = nil
    ) {
        self.condition = condition
        self.temperatureCelsius = temperatureCelsius
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.locationName = locationName
        self.precipMinutesUntil = precipMinutesUntil
    }
}

/// Errors a ``WeatherServiceClient`` can throw.
public enum WeatherServiceError: Error, Sendable, Equatable {
    /// The client is a stub and cannot actually fetch weather.
    /// Thrown exclusively by ``WeatherKitClient`` in Slice 7.
    case notImplemented
    /// Network reached the upstream but the call failed.
    case networkFailure(String)
    /// Upstream responded but the payload could not be parsed.
    case invalidResponse(String)
}
