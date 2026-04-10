import Foundation
import CoreLocation
import RideSimulatorKit

#if canImport(WeatherKit)
import WeatherKit

/// Live ``WeatherServiceClient`` backed by Apple's WeatherKit framework.
///
/// Requires the `com.apple.developer.weatherkit` entitlement on the host app
/// and an active WeatherKit subscription in App Store Connect.
public struct WeatherKitClient: WeatherServiceClient, Sendable {
    public init() {}

    public func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherServiceResponse {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let weather: Weather
        do {
            weather = try await WeatherKit.WeatherService.shared.weather(for: location)
        } catch {
            throw WeatherServiceError.networkFailure(error.localizedDescription)
        }

        let current = weather.currentWeather
        let condition = Self.mapCondition(current.condition)

        // Daily forecast for high/low — fall back to current temp when unavailable.
        var high = current.temperature.converted(to: .celsius).value
        var low = high
        do {
            let daily = try await WeatherKit.WeatherService.shared.weather(
                for: location,
                including: .daily
            )
            if let today = daily.forecast.first {
                high = today.highTemperature.converted(to: .celsius).value
                low = today.lowTemperature.converted(to: .celsius).value
            }
        } catch {
            // Non-fatal: we already have a usable current temp.
        }

        return WeatherServiceResponse(
            condition: condition,
            temperatureCelsius: current.temperature.converted(to: .celsius).value,
            highCelsius: high,
            lowCelsius: low,
            locationName: ""  // CLGeocoder reverse-geocoding is out of scope; caller can enrich.
        )
    }

    // MARK: - Condition mapping

    /// Maps a WeatherKit ``WeatherCondition`` to the app's domain enum.
    ///
    /// WeatherKit exposes many granular conditions; we bucket them into the
    /// six categories the ScramScreen hardware supports.
    static func mapCondition(_ condition: WeatherKit.WeatherCondition) -> WeatherCondition {
        switch condition {
        // Clear
        case .clear, .hot, .mostlyClear:
            return .clear

        // Cloudy
        case .cloudy, .mostlyCloudy, .partlyCloudy, .haze, .smoky, .dust, .windy, .breezy:
            return .cloudy

        // Rain
        case .rain, .heavyRain, .drizzle, .freezingDrizzle, .freezingRain,
             .sunShowers, .hail, .tropicalStorm, .hurricane:
            return .rain

        // Snow
        case .snow, .heavySnow, .flurries, .sleet, .blizzard, .wintryMix,
             .blowingSnow, .frigid:
            return .snow

        // Fog
        case .foggy:
            return .fog

        // Thunderstorm
        case .thunderstorms, .strongStorms, .isolatedThunderstorms, .scatteredThunderstorms:
            return .thunderstorm

        // Catch-all for any future WeatherKit additions.
        @unknown default:
            return .cloudy
        }
    }
}
#endif
