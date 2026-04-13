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
        let nextRain = Self.minutesUntilNextPrecipitation(parsed.hourly)

        return WeatherServiceResponse(
            condition: condition,
            temperatureCelsius: parsed.current.temperature_2m,
            highCelsius: high,
            lowCelsius: low,
            locationName: name,
            precipMinutesUntil: nextRain
        )
    }

    /// Walk the hourly precipitation forecast and return the number of
    /// minutes until the next hour with > 0.1 mm of precipitation, or
    /// nil if none in the forecast horizon.
    private static func minutesUntilNextPrecipitation(_ hourly: OpenMeteoResponse.Hourly?) -> Int? {
        guard let hourly,
              let now = ISO8601Format.parse(hourly.time.first) else { return nil }
        let precipTimes = zip(hourly.time, hourly.precipitation)
        for (timeString, mm) in precipTimes where mm >= 0.1 {
            guard let date = ISO8601Format.parse(timeString) else { continue }
            let secondsAhead = date.timeIntervalSince(now)
            if secondsAhead <= 0 { continue }
            let minutes = Int(secondsAhead / 60)
            if minutes < 240 { return minutes }
            return nil
        }
        return nil
    }

    // MARK: - URL

    private static func makeURL(latitude: Double, longitude: Double) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        c?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "hourly", value: "precipitation"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2"),
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
        case 0:                 return .clear
        case 1, 2:              return .partlyCloudy
        case 3:                 return .overcast
        case 45, 48:            return .fog
        case 51, 53, 55,
             56, 57:            return .drizzle
        case 61, 63, 65,
             66, 67,
             80, 81, 82:        return .rain
        case 71, 73, 75,
             77, 85, 86:        return .snow
        case 95, 96, 99:        return .thunderstorm
        default:                return .cloudy
        }
    }
}

private enum ISO8601Format {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return formatter.date(from: value)
    }
}

// MARK: - JSON DTOs

private struct OpenMeteoResponse: Decodable {
    let current: Current
    let daily: Daily
    let hourly: Hourly?

    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
    }

    struct Daily: Decodable {
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }

    struct Hourly: Decodable {
        let time: [String]
        let precipitation: [Double]
    }
}
