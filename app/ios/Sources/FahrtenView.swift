import ScramCore
import SwiftUI

struct FahrtenView: View {
    private let store: TripHistoryStore
    @State private var trips: [TripSummary] = []

    init(store: TripHistoryStore = TripHistoryStore()) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ScramSpacing.xxl) {
                    Text("Fahrten")
                        .font(.scramTitle)
                        .foregroundStyle(Color.scramTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, ScramSpacing.xxl)

                    if trips.isEmpty {
                        emptyState
                    } else {
                        tripList
                    }
                }
                .padding(.horizontal, ScramSpacing.xl)
                .padding(.bottom, ScramSpacing.xxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.scramBackground)
            .onAppear {
                trips = store.loadAll()
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: ScramSpacing.lg) {
            Spacer()
                .frame(height: 80)
            Image(systemName: "road.lanes")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.scramTextTertiary)
            Text("Noch keine Fahrten")
                .font(.scramTitle)
                .foregroundStyle(Color.scramTextPrimary)
            Text("Deine Fahrten werden hier angezeigt")
                .font(.scramSubhead)
                .foregroundStyle(Color.scramTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trip list

    private var tripList: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Letzte Fahrten")
            VStack(spacing: ScramSpacing.md) {
                ForEach(trips) { trip in
                    NavigationLink(destination: TripDetailView(trip: trip)) {
                        tripCard(trip)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Trip card

    private func tripCard(_ trip: TripSummary) -> some View {
        VStack(spacing: ScramSpacing.md) {
            // Date header
            HStack {
                Text(Self.dateFormatter.string(from: trip.date))
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramTextPrimary)
                Spacer()
                if trip.hasRoute {
                    Image(systemName: "map")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.scramGreen)
                }
            }

            // Primary stats row
            HStack(spacing: ScramSpacing.lg) {
                statItem(
                    icon: "clock",
                    value: Self.formatDuration(trip.duration),
                    label: "Dauer"
                )
                Spacer()
                statItem(
                    icon: "arrow.triangle.swap",
                    value: Self.formatDistance(trip.distanceKm),
                    label: "Distanz"
                )
                Spacer()
                statItem(
                    icon: "speedometer",
                    value: "\(Int(trip.avgSpeedKmh)) km/h",
                    label: "⌀ Tempo"
                )
            }

            // Secondary stats row
            HStack(spacing: ScramSpacing.lg) {
                secondaryStat(
                    label: "Max",
                    value: "\(Int(trip.maxSpeedKmh)) km/h"
                )
                secondaryStat(
                    label: "Anstieg",
                    value: "\(Int(trip.elevationGainM)) m"
                )
                Spacer()
            }
        }
        .padding(ScramSpacing.lg)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
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
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMMM yyyy"
        return formatter
    }()

    static func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        }
        return "\(minutes)min"
    }

    static func formatDistance(_ km: Double) -> String {
        if km >= 100 {
            return "\(Int(km)) km"
        }
        return String(format: "%.1f km", km)
    }
}

// MARK: - Preview

#Preview("With trips") {
    FahrtenView(store: {
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: "FahrtenPreview")!
        defaults.removePersistentDomain(forName: "FahrtenPreview")
        let store = TripHistoryStore(defaults: defaults)
        store.save(TripSummary(
            date: Date(),
            duration: 8100,
            distanceKm: 142.3,
            avgSpeedKmh: 63,
            maxSpeedKmh: 148,
            elevationGainM: 890
        ))
        store.save(TripSummary(
            date: Date().addingTimeInterval(-86400),
            duration: 3600,
            distanceKm: 45.7,
            avgSpeedKmh: 45,
            maxSpeedKmh: 110,
            elevationGainM: 320
        ))
        store.save(TripSummary(
            date: Date().addingTimeInterval(-172800),
            duration: 5400,
            distanceKm: 87.2,
            avgSpeedKmh: 58,
            maxSpeedKmh: 135,
            elevationGainM: 560
        ))
        return store
    }())
}

#Preview("Empty") {
    // swiftlint:disable:next force_unwrapping
    FahrtenView(store: TripHistoryStore(defaults: UserDefaults(suiteName: "FahrtenEmpty")!))
}
