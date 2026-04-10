import CoreLocation
import ScramCore
import SwiftUI
#if canImport(WeatherKit)
import RideSimulatorKit
#endif

// MARK: - Weather tile

extension MehrView {
    var weatherSection: some View {
        Group {
            if let weatherText {
                settingsRow(
                    icon: weatherIcon,
                    title: weatherText
                )
            }
        }
    }

    func fetchWeather() async {
        #if canImport(WeatherKit)
        let locManager = CLLocationManager()
        guard let location = locManager.location else { return }
        let client = WeatherKitClient()
        do {
            let response = try await client.fetchCurrentWeather(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            let geocoder = CLGeocoder()
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            let city = placemarks?.first?.locality ?? ""
            let tempStr = useCelsius
                ? String(format: "%.0f°C", response.temperatureCelsius)
                : String(format: "%.0f°F", response.temperatureCelsius * 9 / 5 + 32)
            weatherIcon = weatherSFSymbol(for: response.condition)
            weatherText = city.isEmpty ? tempStr : "\(city) · \(tempStr)"
        } catch {
            // WeatherKit not available — skip
        }
        #endif
    }

    #if canImport(WeatherKit)
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
    #endif
}
