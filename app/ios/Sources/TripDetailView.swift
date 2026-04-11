import MapKit
import ScramCore
import SwiftUI

struct TripDetailView: View {
    let trip: TripSummary
    @State private var routePoints: [RoutePoint] = []
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var gpxFileURL: URL?

    private let routeStorage = RouteStorage()

    var body: some View {
        ScrollView {
            VStack(spacing: ScramSpacing.xxl) {
                tripSummaryCard
                if !routePoints.isEmpty {
                    routeMap
                    elevationProfile
                    speedProfile
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !routePoints.isEmpty, let url = gpxFileURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            if let points = routeStorage.load(tripId: trip.id) {
                routePoints = points
                gpxFileURL = GPXExporter.exportToFile(points: points, trip: trip)
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

    // MARK: - Elevation profile

    private var elevationProfile: some View {
        let altitudes = routePoints.compactMap { $0.altitude }
        let distances = cumulativeDistances(for: routePoints)
        return profileChart(
            title: "Elevation",
            unit: "m",
            values: altitudes,
            distances: distances,
            lineColor: Color.scramGreen
        )
    }

    // MARK: - Speed profile

    private var speedProfile: some View {
        // Convert speed from m/s to km/h
        let speeds = routePoints.compactMap { $0.speed.map { $0 * 3.6 } }
        let distances = cumulativeDistances(for: routePoints)
        return profileChart(
            title: "Speed",
            unit: "km/h",
            values: speeds,
            distances: distances,
            lineColor: Color.scramBlue
        )
    }

    // MARK: - Profile chart helper

    @ViewBuilder
    private func profileChart(
        title: String,
        unit: String,
        values: [Double],
        distances: [Double],
        lineColor: Color
    ) -> some View {
        if values.count >= 2 {
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 1
            let range = max(maxVal - minVal, 1)

            VStack(alignment: .leading, spacing: ScramSpacing.sm) {
                Text(title)
                    .font(.scramCaption)
                    .foregroundStyle(Color.scramTextSecondary)

                ZStack(alignment: .topLeading) {
                    // Y-axis labels
                    VStack {
                        Text("\(Int(maxVal)) \(unit)")
                            .font(.scramCaption)
                            .foregroundStyle(Color.scramTextTertiary)
                        Spacer()
                        Text("\(Int(minVal)) \(unit)")
                            .font(.scramCaption)
                            .foregroundStyle(Color.scramTextTertiary)
                    }
                    .frame(width: 60, alignment: .trailing)

                    // Chart line
                    GeometryReader { geo in
                        let width = geo.size.width - 68  // account for label width + padding
                        let height = geo.size.height
                        let maxDist = distances.last ?? 1

                        Path { path in
                            // We need to match values to distances — values are compactMapped
                            // so they may be fewer than distances. Build paired data.
                            let paired = pairedData(
                                values: values,
                                allDistances: distances,
                                routePoints: routePoints,
                                isAltitude: title == "Elevation"
                            )

                            for (idx, pair) in paired.enumerated() {
                                let px = 68 + (pair.distance / maxDist) * width
                                let py = height - ((pair.value - minVal) / range) * height
                                if idx == 0 {
                                    path.move(to: CGPoint(x: px, y: py))
                                } else {
                                    path.addLine(to: CGPoint(x: px, y: py))
                                }
                            }
                        }
                        .stroke(lineColor, lineWidth: 2)
                    }
                }
                .frame(height: 120)
            }
            .padding(ScramSpacing.lg)
            .background(Color.scramSurface)
            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
        }
    }

    // MARK: - Distance / data helpers

    /// Computes cumulative haversine distances in km for each route point.
    private func cumulativeDistances(for points: [RoutePoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var distances: [Double] = [0]
        var total = 0.0
        for idx in 1..<points.count {
            let segmentKm = GeoMath.haversineMeters(
                lat1: points[idx - 1].latitude,
                lon1: points[idx - 1].longitude,
                lat2: points[idx].latitude,
                lon2: points[idx].longitude
            ) / 1000.0  // convert to km
            total += segmentKm
            distances.append(total)
        }
        return distances
    }

    /// Pairs values (which may be a subset due to compactMap) with their
    /// corresponding cumulative distances.
    private func pairedData(
        values: [Double],
        allDistances: [Double],
        routePoints: [RoutePoint],
        isAltitude: Bool
    ) -> [(distance: Double, value: Double)] {
        var result: [(distance: Double, value: Double)] = []
        var valueIndex = 0
        for (idx, point) in routePoints.enumerated() {
            guard valueIndex < values.count else { break }
            let hasValue = isAltitude ? point.altitude != nil : point.speed != nil
            if hasValue, idx < allDistances.count {
                result.append((distance: allDistances[idx], value: values[valueIndex]))
                valueIndex += 1
            }
        }
        return result
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
