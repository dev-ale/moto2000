import CoreLocation
import RideSimulatorKit
import ScramCore
import SwiftUI

// MARK: - Weather tile

extension MehrView {
    var weatherSection: some View {
        settingsRow(
            icon: weatherIcon,
            title: weatherText ?? "Weather: waiting for GPS…"
        )
    }

    func fetchWeather() async {
        let manager = CLLocationManager()
        let auth = manager.authorizationStatus
        guard auth == .authorizedWhenInUse || auth == .authorizedAlways else {
            weatherIcon = "location.slash"
            weatherText = "Location not authorized"
            return
        }

        guard let location = manager.location else {
            // CLLocationManager.location is populated once CoreLocation
            // has a fix. Surface the missing-fix state so the user can
            // tell whether the failure is GPS or weather.
            weatherIcon = "location.magnifyingglass"
            weatherText = "Waiting for GPS fix…"
            return
        }

        weatherIcon = "cloud.fill"
        weatherText = "Fetching weather…"

        let client = OpenMeteoClient()
        do {
            let response = try await client.fetchCurrentWeather(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            let tempStr = useCelsius
                ? String(format: "%.0f°C", response.temperatureCelsius)
                : String(format: "%.0f°F", response.temperatureCelsius * 9 / 5 + 32)
            weatherIcon = weatherSFSymbol(for: response.condition)
            let city = response.locationName.isEmpty
                ? String(format: "%.4f, %.4f",
                         location.coordinate.latitude,
                         location.coordinate.longitude)
                : response.locationName
            weatherText = "\(city) · \(tempStr)"
        } catch {
            weatherIcon = "exclamationmark.triangle"
            weatherText = "Weather error: \(error.localizedDescription)"
        }
    }

    func weatherSFSymbol(
        for condition: RideSimulatorKit.WeatherCondition
    ) -> String {
        switch condition {
        case .clear: "sun.max.fill"
        case .cloudy: "cloud.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .fog: "cloud.fog.fill"
        case .thunderstorm: "cloud.bolt.fill"
        }
    }
}
