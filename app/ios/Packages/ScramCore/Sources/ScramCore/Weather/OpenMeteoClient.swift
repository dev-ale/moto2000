import CoreLocation
import Foundation
import RideSimulatorKit

/// Live ``WeatherServiceClient`` backed by the free Open-Meteo API.
///
/// Open-Meteo requires no API key and has a generous fair-use limit. The
/// location name is filled in via ``CLGeocoder`` reverse geocoding.
public final class OpenMeteoClient: WeatherServiceClient, @unchecked Sendable {
    public init() {}

    public func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherServiceResponse {
        guard let url = Self.makeURL(latitude: latitude, longitude: longitude) else {
            throw WeatherServiceError.networkFailure("invalid url")
        }

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw WeatherServiceError.networkFailure(error.localizedDescription)
        }

        let parsed: OpenMeteoResponse
        do {
            parsed = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        } catch {
            throw WeatherServiceError.invalidResponse(error.localizedDescription)
        }

        let condition = Self.mapCondition(parsed.current.weather_code)
        let high = parsed.daily.temperature_2m_max.first ?? parsed.current.temperature_2m
        let low = parsed.daily.temperature_2m_min.first ?? parsed.current.temperature_2m
        let name = await Self.reverseGeocode(latitude: latitude, longitude: longitude)

        return WeatherServiceResponse(
            condition: condition,
            temperatureCelsius: parsed.current.temperature_2m,
            highCelsius: high,
            lowCelsius: low,
            locationName: name
        )
    }

    // MARK: - URL

    private static func makeURL(latitude: Double, longitude: Double) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        c?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        return c?.url
    }

    // MARK: - Reverse geocoding

    private static func reverseGeocode(latitude: Double, longitude: Double) async -> String {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        return await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                let name = placemarks?.first?.locality
                    ?? placemarks?.first?.subAdministrativeArea
                    ?? placemarks?.first?.administrativeArea
                    ?? ""
                continuation.resume(returning: name)
            }
        }
    }

    // MARK: - WMO weather code → app condition

    /// https://open-meteo.com/en/docs WMO Weather interpretation codes.
    static func mapCondition(_ code: Int) -> WeatherCondition {
        switch code {
        case 0, 1: return .clear
        case 2, 3: return .cloudy
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return .rain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .thunderstorm
        default: return .cloudy
        }
    }
}

// MARK: - JSON DTOs

private struct OpenMeteoResponse: Decodable {
    let current: Current
    let daily: Daily

    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
    }

    struct Daily: Decodable {
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }
}
