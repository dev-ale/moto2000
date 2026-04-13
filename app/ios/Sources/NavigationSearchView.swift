#if canImport(MapKit)
import MapKit
import SwiftUI

/// Search-and-navigate card for the Home tab.
///
/// Uses `MKLocalSearchCompleter` for autocomplete suggestions and lets
/// the user start/stop a navigation session. When navigation is active
/// the card shows the destination name and a stop button.
struct NavigationSearchView: View {
    @StateObject private var vm = NavigationSearchViewModel()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: ScramSpacing.lg) {
            SectionHeader(title: "Navigation")

            if vm.isNavigating {
                activeNavigationCard
            } else {
                searchCard
            }
        }
    }

    // MARK: - Search state

    private var searchCard: some View {
        VStack(spacing: ScramSpacing.md) {
            // Search text field
            HStack(spacing: ScramSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.scramTextTertiary)

                TextField("Search destination", text: $vm.searchText)
                    .font(.scramBody)
                    .foregroundStyle(Color.scramTextPrimary)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)

                if !vm.searchText.isEmpty {
                    Button { vm.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.scramTextTertiary)
                    }
                }
            }
            .padding(.horizontal, ScramSpacing.md)
            .padding(.vertical, ScramSpacing.sm)
            .background(Color.scramSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))

            // Autocomplete results
            if !vm.completions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(vm.completions.prefix(5), id: \.self) { completion in
                        Button {
                            isSearchFocused = false
                            vm.select(completion)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .font(.scramBody)
                                        .foregroundStyle(Color.scramTextPrimary)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.scramCaption)
                                            .foregroundStyle(Color.scramTextSecondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(Color.scramTextTertiary)
                                    .font(.scramCaption)
                            }
                            .padding(.horizontal, ScramSpacing.md)
                            .padding(.vertical, ScramSpacing.sm)
                        }

                        if completion != vm.completions.prefix(5).last {
                            Divider()
                                .background(Color.scramBorder)
                        }
                    }
                }
                .background(Color.scramSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.cardSmall))
            }

            // Selected destination + "Los" button
            if let selected = vm.selectedDestination {
                VStack(spacing: ScramSpacing.sm) {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(Color.scramGreen)
                        Text(selected.name)
                            .font(.scramBody)
                            .foregroundStyle(Color.scramTextPrimary)
                        Spacer()
                    }

                    Button {
                        vm.startNavigation()
                    } label: {
                        Text("Go")
                            .font(.scramHeadline)
                            .foregroundStyle(Color.scramBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, ScramSpacing.md)
                    }
                    .background(Color.scramGreen)
                    .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
                }
            }
        }
        .padding(ScramSpacing.xxl)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }

    // MARK: - Active navigation state

    private func routeStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.scramHeadline)
                .foregroundStyle(Color.scramTextPrimary)
            Text(label)
                .font(.scramCaption)
                .foregroundStyle(Color.scramTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var activeNavigationCard: some View {
        VStack(spacing: ScramSpacing.md) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundStyle(Color.scramGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Navigation active")
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextSecondary)
                    Text(vm.destinationName)
                        .font(.scramHeadline)
                        .foregroundStyle(Color.scramTextPrimary)
                }
                Spacer()
            }

            if !vm.routeDistanceText.isEmpty {
                HStack(spacing: ScramSpacing.lg) {
                    routeStat("Distance", vm.routeDistanceText)
                    routeStat("Time", vm.routeDurationText)
                    routeStat("ETA", vm.routeETAText)
                }
            } else if !vm.diagnosticStatus.isEmpty {
                Text(vm.diagnosticStatus)
                    .font(.scramCaption)
                    .foregroundStyle(Color.scramTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let coord = vm.activeDestinationCoordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coord,
                    latitudinalMeters: 4000,
                    longitudinalMeters: 4000
                ))) {
                    Marker(vm.destinationName, coordinate: coord)
                        .tint(Color.scramGreen)
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .flat))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.cardSmall))
            }

            Button {
                vm.stopNavigation()
            } label: {
                Text("Stop Navigation")
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ScramSpacing.md)
            }
            .background(Color.scramRedBg)
            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
        }
        .padding(ScramSpacing.xxl)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }
}

// MARK: - View Model

/// Drives the search UI and navigation lifecycle.
///
/// Wraps `MKLocalSearchCompleter` for autocomplete and resolves the
/// selected completion to a coordinate via `MKLocalSearch`.
@MainActor
final class NavigationSearchViewModel: NSObject, ObservableObject {
    @Published var searchText: String = "" {
        didSet { completer.queryFragment = searchText }
    }
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var selectedDestination: SelectedDestination?
    @Published var isNavigating: Bool = false
    @Published var destinationName: String = ""
    @Published var activeDestinationCoordinate: CLLocationCoordinate2D?
    @Published var diagnosticStatus: String = ""
    @Published var routeDistanceText: String = ""
    @Published var routeDurationText: String = ""
    @Published var routeETAText: String = ""

    struct SelectedDestination {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        // Bias results toward Basel area
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.56, longitude: 7.59),
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )

        // Listen for external navigation starts (e.g. from Tank gas stations)
        NotificationCenter.default.addObserver(
            forName: .scramNavigationStartRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let name = notification.userInfo?["name"] as? String else { return }
            self?.destinationName = name
            self?.isNavigating = true
            self?.searchText = ""
            self?.completions = []
            if let lat = notification.userInfo?["latitude"] as? Double,
               let lon = notification.userInfo?["longitude"] as? Double {
                self?.activeDestinationCoordinate = CLLocationCoordinate2D(
                    latitude: lat, longitude: lon
                )
            }
        }

        // Live status updates from NavigationService for in-app debugging.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("scramNavigationStatusUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let msg = note.userInfo?["message"] as? String {
                self?.diagnosticStatus = msg
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("scramNavigationRouteReady"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let meters = info["distanceMeters"] as? Double,
                  let seconds = info["durationSeconds"] as? Double else { return }
            self?.routeDistanceText = Self.formatDistance(meters)
            self?.routeDurationText = Self.formatDuration(seconds)
            self?.routeETAText = Self.formatETA(in: seconds)
        }
    }

    private static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let remMinutes = totalMinutes % 60
            return "\(hours) h \(remMinutes) min"
        }
        return "\(totalMinutes) min"
    }

    private static func formatETA(in seconds: Double) -> String {
        let arrival = Date().addingTimeInterval(seconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: arrival)
    }

    func select(_ completion: MKLocalSearchCompletion) {
        searchText = completion.title
        completions = []
        completer.queryFragment = ""

        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        Task { @MainActor [weak self] in
            let response = try? await search.start()
            guard let item = response?.mapItems.first,
                  let self else { return }
            self.selectedDestination = SelectedDestination(
                name: completion.title,
                coordinate: item.placemark.coordinate
            )
        }
    }

    func startNavigation() {
        guard let dest = selectedDestination else { return }
        destinationName = dest.name
        activeDestinationCoordinate = dest.coordinate
        isNavigating = true
        searchText = ""
        completions = []
        selectedDestination = nil

        // The actual NavigationService.start() call is the responsibility
        // of the parent coordinator / ScreenController that observes this
        // view model's published state. This view model only drives the
        // UI state machine.
        // Persist for Live Preview to pick up
        UserDefaults.standard.set(dest.coordinate.latitude, forKey: "scramNav.lat")
        UserDefaults.standard.set(dest.coordinate.longitude, forKey: "scramNav.lon")
        UserDefaults.standard.set(true, forKey: "scramNav.active")

        NotificationCenter.default.post(
            name: .scramNavigationStartRequested,
            object: nil,
            userInfo: [
                "latitude": dest.coordinate.latitude,
                "longitude": dest.coordinate.longitude,
                "name": dest.name,
            ]
        )
    }

    func stopNavigation() {
        isNavigating = false
        activeDestinationCoordinate = nil
        routeDistanceText = ""
        routeDurationText = ""
        routeETAText = ""
        diagnosticStatus = ""
        destinationName = ""
        UserDefaults.standard.set(false, forKey: "scramNav.active")
        NotificationCenter.default.post(
            name: .scramNavigationStopRequested,
            object: nil
        )
    }
}

extension NavigationSearchViewModel: @preconcurrency MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // MKLocalSearchCompletion is not Sendable; wrap to cross isolation.
        struct UnsafeResults: @unchecked Sendable {
            let value: [MKLocalSearchCompletion]
        }
        let wrapped = UnsafeResults(value: completer.results)
        Task { @MainActor [weak self] in
            self?.completions = wrapped.value
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Silently ignore — the user can keep typing.
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let scramNavigationStartRequested = Notification.Name("scramNavigationStartRequested")
    static let scramNavigationStopRequested = Notification.Name("scramNavigationStopRequested")
    static let scramSwitchToHomeTab = Notification.Name("scramSwitchToHomeTab")
}
#endif
