import CoreLocation
import MapKit
import SwiftUI

// MARK: - Gas Station model

struct GasStation: Identifiable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double

    var distanceFormatted: String {
        if distanceMeters >= 1000 {
            return String(format: "%.1f km", distanceMeters / 1000)
        }
        return "\(Int(distanceMeters)) m"
    }
}

// MARK: - Nearby stations UI + search

extension TankView {
    var nearbyStationsSection: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Tankstellen")

            if loadingStations {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Color.scramGreen)
                    Spacer()
                }
                .padding(ScramSpacing.xl)
                .background(Color.scramSurface)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
            } else if nearbyStations.isEmpty {
                HStack(spacing: ScramSpacing.md) {
                    Image(systemName: "fuelpump.slash")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.scramTextTertiary)
                        .frame(width: 24)
                    Text("No stations found")
                        .font(.scramBody)
                        .foregroundStyle(Color.scramTextSecondary)
                    Spacer()
                }
                .padding(ScramSpacing.lg)
                .background(Color.scramSurface)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
            } else {
                VStack(spacing: 1) {
                    ForEach(nearbyStations) { station in
                        Button {
                            navigateToStation(station)
                        } label: {
                            stationRow(station)
                        }
                    }
                }
                .background(Color.scramSurface)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
            }
        }
    }

    func stationRow(_ station: GasStation) -> some View {
        HStack(spacing: ScramSpacing.md) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.scramGreen)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: ScramSpacing.xs) {
                Text(station.name)
                    .font(.scramBody)
                    .foregroundStyle(Color.scramTextPrimary)
                    .lineLimit(1)

                Text(station.distanceFormatted)
                    .font(.scramCaption)
                    .foregroundStyle(Color.scramTextTertiary)
            }

            Spacer()

            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.scramGreen)
        }
        .padding(ScramSpacing.lg)
    }

    func searchNearbyStations() async {
        loadingStations = true
        defer { loadingStations = false }

        // Use existing location or fall back to Basel
        let coordinate = CLLocationManager().location?.coordinate
            ?? CLLocationCoordinate2D(latitude: 47.56, longitude: 7.59)
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "gas station"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 10_000,
            longitudinalMeters: 10_000
        )

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            let sorted = response.mapItems
                .compactMap { item -> GasStation? in
                    guard let name = item.name else { return nil }
                    let dist = location.distance(from: CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    ))
                    return GasStation(
                        id: UUID(),
                        name: name,
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude,
                        distanceMeters: dist
                    )
                }
                .sorted { $0.distanceMeters < $1.distanceMeters }

            nearbyStations = Array(sorted.prefix(3))
        } catch {
            nearbyStations = []
        }
    }

    func navigateToStation(_ station: GasStation) {
        UserDefaults.standard.set(station.latitude, forKey: "scramNav.lat")
        UserDefaults.standard.set(station.longitude, forKey: "scramNav.lon")
        UserDefaults.standard.set(true, forKey: "scramNav.active")

        NotificationCenter.default.post(
            name: .scramNavigationStartRequested,
            object: nil,
            userInfo: [
                "latitude": station.latitude,
                "longitude": station.longitude,
                "name": station.name,
            ]
        )

        // Switch to Home tab
        NotificationCenter.default.post(
            name: .scramSwitchToHomeTab,
            object: nil
        )
    }
}
