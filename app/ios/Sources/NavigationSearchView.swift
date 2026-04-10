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

                TextField("Ziel suchen", text: $vm.searchText)
                    .font(.scramBody)
                    .foregroundStyle(Color.scramTextPrimary)
                    .autocorrectionDisabled()

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
                        Text("Los")
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

    private var activeNavigationCard: some View {
        VStack(spacing: ScramSpacing.md) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundStyle(Color.scramGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Navigation aktiv")
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextSecondary)
                    Text(vm.destinationName)
                        .font(.scramHeadline)
                        .foregroundStyle(Color.scramTextPrimary)
                }
                Spacer()
            }

            Button {
                vm.stopNavigation()
            } label: {
                Text("Navigation beenden")
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

    struct SelectedDestination {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .pointOfInterest
    }

    func select(_ completion: MKLocalSearchCompletion) {
        searchText = completion.title
        completions = []

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
        isNavigating = true
        searchText = ""
        completions = []
        selectedDestination = nil

        // The actual NavigationService.start() call is the responsibility
        // of the parent coordinator / ScreenController that observes this
        // view model's published state. This view model only drives the
        // UI state machine.
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
        destinationName = ""
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
}
#endif
