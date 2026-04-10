import BLEProtocol
import SwiftUI

/// Live display preview — shows what the ESP32 AMOLED would render
/// using real sensor data from the phone.
struct DisplayPreviewView: View {
    @Binding var isPresented: Bool
    @State private var session = LivePreviewSession()
    @State private var currentIndex: Int = 0

    private let gold = Color(hex: 0xEBAB00)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                // Close button top-right
                HStack {
                    Spacer()
                    Button {
                        session.stop()
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(hex: 0x444444))
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 12)
                }

                Spacer()

                screenLabel
                displayCircle
                navigationControls

                Spacer()
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
                .frame(width: 252, height: 252)
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
        withAnimation(.easeInOut(duration: 0.15)) {
            currentIndex = (currentIndex + offset + count) % count
        }
    }

    // MARK: - Lean angle with manual calibration

    @ViewBuilder
    private var leanAngleScreen: some View {
        if !session.leanCalibrated {
            Button {
                session.calibrateLeanAngle()
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 36))
                        .foregroundStyle(gold)
                    Text("Tippen zum\nKalibrieren")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
            }
        } else if let data = session.latestLeanAngle {
            LeanAngleScreenContent(screenData: data)
        } else {
            PreviewWaitingIndicator()
        }
    }

    // MARK: - Bezel

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
                        colors: [
                            Color(hex: 0x2A2A2A),
                            Color(hex: 0x1A1A1A),
                            Color(hex: 0x151515),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 290, height: 290)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x444444),
                            Color(hex: 0x222222),
                            Color(hex: 0x111111),
                        ],
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
        case .speedHeading:
            sensorScreen(session.latestSpeed, SpeedScreenContent.init)
        case .compass:
            sensorScreen(session.latestCompass, CompassScreenContent.init)
        case .tripStats:
            sensorScreen(session.latestTripStats, TripStatsScreenContent.init)
        case .leanAngle:
            leanAngleScreen
        case .clock:
            sensorScreen(session.latestClock, ClockScreenContent.init)
        case .altitude:
            sensorScreen(session.latestAltitude, AltitudeScreenContent.init)
        case .weather:
            optionalScreen(session.latestWeather, "Wetter laden...", WeatherScreenContent.init)
        case .music:
            optionalScreen(session.latestMusic, "Keine Musik", MusicScreenContent.init)
        case .fuelEstimate:
            optionalScreen(session.latestFuel, "Keine Tankdaten", FuelScreenContent.init)
        case .appointment:
            optionalScreen(
                session.latestAppointment, "Keine Termine", AppointmentScreenContent.init
            )
        default: PreviewPlaceholder(text: "—")
        }
    }
    // swiftlint:enable cyclomatic_complexity

    @ViewBuilder
    private func sensorScreen<T, V: View>(_ value: T?, _ builder: (T) -> V) -> some View {
        if let value {
            builder(value)
        } else {
            PreviewWaitingIndicator()
        }
    }

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
