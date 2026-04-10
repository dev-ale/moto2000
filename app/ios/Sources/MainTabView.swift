import BLECentralClient
import ScramCore
import SwiftUI

enum ScramTab: String, CaseIterable {
    case home = "Home"
    case screens = "Screens"
    case fahrten = "Fahrten"
    case tank = "Tank"
    case mehr = "Mehr"

    var icon: String {
        switch self {
        case .home: return "house"
        case .screens: return "circle.grid.2x2"
        case .fahrten: return "road.lanes"
        case .tank: return "fuelpump"
        case .mehr: return "ellipsis"
        }
    }
}

struct MainTabView: View {
    @State var connection: ConnectionViewModel
    @State private var selectedTab: ScramTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(ScramTab.allCases, id: \.self) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                    }
                    .tag(tab)
            }
        }
        .tint(Color.scramGreen)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 0.95)

            let normal = UIColor(Color.scramTextTertiary)
            let selected = UIColor(Color.scramGreen)

            appearance.stackedLayoutAppearance.normal.iconColor = normal
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normal]
            appearance.stackedLayoutAppearance.selected.iconColor = selected
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selected]

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func tabContent(for tab: ScramTab) -> some View {
        switch tab {
        case .home:
            HomeView(connection: connection)
        case .screens:
            ScreensView()
        case .fahrten:
            FahrtenView()
        case .tank:
            TankView(fuelLog: FuelLog(store: DocumentsFuelLogStore()))
        case .mehr:
            MehrView(connection: connection)
        }
    }
}

struct PlaceholderTab: View {
    let title: String
    let icon: String
    let subtitle: String

    var body: some View {
        VStack(spacing: ScramSpacing.lg) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.scramTextTertiary)
            Text(title)
                .font(.scramTitle)
                .foregroundStyle(Color.scramTextPrimary)
            Text(subtitle)
                .font(.scramSubhead)
                .foregroundStyle(Color.scramTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scramBackground)
    }
}
