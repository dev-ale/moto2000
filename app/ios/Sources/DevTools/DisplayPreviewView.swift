import BLEProtocol
import SwiftUI

/// Debug-only live display preview that renders real sensor data
/// in a round AMOLED-style circle, approximating what the ESP32 display shows.
struct DisplayPreviewView: View {
    @State private var session = LivePreviewSession()
    @State private var currentIndex: Int = 0

    private let gold = Color(hex: 0xEBAB00)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                screenLabel
                displayCircle
                navigationControls

                Spacer()

                dismissButton
            }
        }
        .gesture(swipeGesture)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .statusBarHidden()
    }

    private var currentScreenID: ScreenID {
        session.availableScreens[currentIndex]
    }

    // MARK: - Top-level layout pieces

    private var screenLabel: some View {
        Text(session.displayName(for: currentScreenID))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(gold)
            .textCase(.uppercase)
            .tracking(1.5)
    }

    private var displayCircle: some View {
        ZStack {
            displayBezel
            displayScreen
            screenContent(for: currentScreenID)
                .frame(width: 240, height: 240)
                .clipShape(Circle())
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 40) {
            Button { navigate(by: -1) } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(hex: 0x333333))
            }

            Text("\(currentIndex + 1) / \(session.availableScreens.count)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: 0x666666))

            Button { navigate(by: 1) } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(hex: 0x333333))
            }
        }
    }

    private var dismissButton: some View {
        Button("Close") { session.stop() }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color(hex: 0x666666))
            .padding(.bottom, 32)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onEnded { value in
                if value.translation.width < -30 {
                    navigate(by: 1)
                } else if value.translation.width > 30 {
                    navigate(by: -1)
                }
            }
    }

    private func navigate(by offset: Int) {
        let count = session.availableScreens.count
        withAnimation(.easeInOut(duration: 0.2)) {
            currentIndex = (currentIndex + offset + count) % count
        }
    }

    // MARK: - Bezel (reuses ScreensView style)

    private var displayBezel: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x0A0A0A))
                .frame(width: 290, height: 290)
                .shadow(color: gold.opacity(0.08), radius: 30)
                .shadow(color: .black.opacity(0.6), radius: 20, y: 10)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x2A2A2A), Color(hex: 0x1A1A1A), Color(hex: 0x151515)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 290, height: 290)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: 0x444444), Color(hex: 0x222222), Color(hex: 0x111111)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .frame(width: 290, height: 290)
        }
    }

    private var displayScreen: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x050505))
                .frame(width: 264, height: 264)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x0C0C0C), Color(hex: 0x080808)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 132
                    )
                )
                .frame(width: 258, height: 258)
        }
    }

    // MARK: - Screen content router

    // swiftlint:disable cyclomatic_complexity
    @ViewBuilder
    private func screenContent(for screenID: ScreenID) -> some View {
        switch screenID {
        case .speedHeading: sensorScreen(session.latestSpeed, SpeedScreenContent.init)
        case .compass: sensorScreen(session.latestCompass, CompassScreenContent.init)
        case .tripStats: sensorScreen(session.latestTripStats, TripStatsScreenContent.init)
        case .leanAngle: sensorScreen(session.latestLeanAngle, LeanAngleScreenContent.init)
        case .clock: sensorScreen(session.latestClock, ClockScreenContent.init)
        case .altitude: sensorScreen(session.latestAltitude, AltitudeScreenContent.init)
        case .weather: optionalScreen(session.latestWeather, "Waiting for weather...", WeatherScreenContent.init)
        case .music: optionalScreen(session.latestMusic, "No music playing", MusicScreenContent.init)
        case .fuelEstimate: optionalScreen(session.latestFuel, "No fuel data", FuelScreenContent.init)
        case .navigation: optionalScreen(session.latestNav, "No navigation active", NavScreenContent.init)
        case .appointment:
            optionalScreen(session.latestAppointment, "No appointments", AppointmentScreenContent.init)
        case .incomingCall:
            optionalScreen(session.latestIncomingCall, "No calls", IncomingCallScreenContent.init)
        case .blitzer:
            optionalScreen(session.latestBlitzer, "No speed cameras nearby", BlitzerScreenContent.init)
        @unknown default: PreviewPlaceholder(text: "Unknown")
        }
    }
    // swiftlint:enable cyclomatic_complexity

    /// Shows a sensor-backed screen with a spinner while waiting for first data.
    @ViewBuilder
    private func sensorScreen<T, V: View>(_ value: T?, _ builder: (T) -> V) -> some View {
        if let value {
            builder(value)
        } else {
            PreviewWaitingIndicator()
        }
    }

    /// Shows an optional-data screen with a placeholder message when no data.
    @ViewBuilder
    private func optionalScreen<T, V: View>(
        _ value: T?,
        _ placeholder: String,
        _ builder: (T) -> V
    ) -> some View {
        if let value {
            builder(value)
        } else {
            PreviewPlaceholder(text: placeholder)
        }
    }
}
