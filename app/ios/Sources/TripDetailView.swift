import MapKit
import ScramCore
import SwiftUI

struct TripDetailView: View {
    let trip: TripSummary
    @State private var routePoints: [RoutePoint] = []
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    private let routeStorage = RouteStorage()

    var body: some View {
        ScrollView {
            VStack(spacing: ScramSpacing.xxl) {
                tripSummaryCard
                if !routePoints.isEmpty {
                    routeMap
                }
            }
            .padding(.horizontal, ScramSpacing.xl)
            .padding(.vertical, ScramSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scramBackground)
        .navigationTitle(Self.dateFormatter.string(from: trip.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if let points = routeStorage.load(tripId: trip.id) {
                routePoints = points
            }
        }
    }

    // MARK: - Trip summary card

    private var tripSummaryCard: some View {
        VStack(spacing: ScramSpacing.md) {
            HStack(spacing: ScramSpacing.lg) {
                statItem(icon: "clock", value: FahrtenView.formatDuration(trip.duration), label: "Duration")
                Spacer()
                statItem(
                    icon: "arrow.triangle.swap",
                    value: FahrtenView.formatDistance(trip.distanceKm),
                    label: "Distance"
                )
                Spacer()
                statItem(icon: "speedometer", value: "\(Int(trip.avgSpeedKmh)) km/h", label: "Avg Speed")
            }

            HStack(spacing: ScramSpacing.lg) {
                secondaryStat(label: "Max", value: "\(Int(trip.maxSpeedKmh)) km/h")
                secondaryStat(label: "Ascent", value: "\(Int(trip.elevationGainM)) m")
                Spacer()
            }
        }
        .padding(ScramSpacing.lg)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }

    // MARK: - Route map

    private var routeMap: some View {
        Map(position: $mapCameraPosition) {
            MapPolyline(coordinates: routePoints.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            })
            .stroke(Color.scramGreen, lineWidth: 3)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
        .onAppear {
            fitMapToRoute()
        }
    }

    private func fitMapToRoute() {
        guard !routePoints.isEmpty else { return }
        let coords = routePoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude
        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.005)
        )
        mapCameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - Stat helpers

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: ScramSpacing.xs) {
            HStack(spacing: ScramSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.scramGreen)
                Text(value)
                    .font(.scramBody)
                    .foregroundStyle(Color.scramTextPrimary)
            }
            Text(label)
                .font(.scramCaption)
                .foregroundStyle(Color.scramTextTertiary)
        }
    }

    private func secondaryStat(label: String, value: String) -> some View {
        HStack(spacing: ScramSpacing.xs) {
            Text(label)
                .font(.scramCaption)
                .foregroundStyle(Color.scramTextTertiary)
            Text(value)
                .font(.scramCaption)
                .foregroundStyle(Color.scramTextSecondary)
        }
    }

    // MARK: - Formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
}
