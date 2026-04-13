import BLECentralClient
import MapKit
import SwiftUI

struct HomeView: View {
    @State var connection: ConnectionViewModel
    let rideCoordinator: RideSessionCoordinator

    @State private var showLivePreview = false
    #if DEBUG
    @State private var showSimulator = false
    @State private var showScreenPicker = false
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: ScramSpacing.xxl) {
                // MARK: - Connection pill + title

                ConnectionPill(connected: connection.isConnected)
                    .animation(.easeInOut(duration: 0.3), value: connection.isConnected)
                    .padding(.top, ScramSpacing.xxl)

                // MARK: - Main card

                if connection.isPaired {
                    connectedCard
                } else {
                    setupCard
                }

                // MARK: - Navigation search

                NavigationSearchView()

                // MARK: - Quick stats (only when paired)

                if connection.isPaired {
                    HStack(spacing: ScramSpacing.sm) {
                        StatCard(
                            value: connection.isConnected ? "80%" : "--",
                            label: "Brightness"
                        )
                        StatCard(value: "Day", label: "Mode")
                        StatCard(
                            value: connection.firmwareVersion?.versionString ?? "--",
                            label: "Firmware"
                        )
                    }
                }

                // MARK: - Live Preview

                livePreviewSection

                #if DEBUG
                debugSection
                #endif
            }
            .padding(.horizontal, ScramSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scramBackground)
        .onAppear {
            connection.startObserving()
        }
    }

    // MARK: - Setup card (not yet paired)

    private var setupCard: some View {
        VStack(spacing: ScramSpacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.scramGreen.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: "plus.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.scramGreen)
            }

            VStack(spacing: ScramSpacing.sm) {
                Text("Pair Display")
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramTextPrimary)

                Text("Tap to pair your ScramScreen display")
                    .font(.scramSubhead)
                    .foregroundStyle(Color.scramTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Button { connection.showPicker() } label: {
                Text("Add Device")
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ScramSpacing.md)
            }
            .background(Color.scramGreen)
            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
        }
        .padding(ScramSpacing.xxl)
        .frame(maxWidth: .infinity)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }

    // MARK: - Connected/paired card

    @ViewBuilder private var connectedCard: some View {
        if case .connected = connection.state {
            compactConnectedCard
        } else {
            fullConnectedCard
        }
    }

    /// Slim row used while the link is up — frees vertical space for
    /// navigation, screens, and stats below.
    private var compactConnectedCard: some View {
        HStack(spacing: ScramSpacing.md) {
            Image(systemName: connection.statusIcon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(connection.statusColor)
            Text(connection.accessoryManager.deviceName)
                .font(.scramBody)
                .foregroundStyle(Color.scramTextPrimary)
            Spacer()
            Button { connection.disconnect() } label: {
                Text("Disconnect")
                    .font(.scramCaption)
                    .foregroundStyle(Color.scramRed)
                    .padding(.horizontal, ScramSpacing.md)
                    .padding(.vertical, ScramSpacing.sm)
                    .background(Color.scramRedBg)
                    .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
            }
        }
        .padding(.horizontal, ScramSpacing.lg)
        .padding(.vertical, ScramSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }

    private var fullConnectedCard: some View {
        VStack(spacing: ScramSpacing.xl) {
            ZStack {
                Circle()
                    .fill(connection.statusColor.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: connection.statusIcon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(connection.statusColor)
                    .symbolEffect(.pulse, isActive: connection.healthLevel == .degraded)
            }

            VStack(spacing: ScramSpacing.sm) {
                Text(connection.accessoryManager.deviceName)
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramTextPrimary)

                Text(connection.statusText)
                    .font(.scramSubhead)
                    .foregroundStyle(connection.statusColor)
            }

            // Action buttons
            switch connection.state {
            case .idle, .disconnected:
                HStack(spacing: ScramSpacing.sm) {
                    Button { connection.connect() } label: {
                        Text("Connect")
                            .font(.scramHeadline)
                            .foregroundStyle(Color.scramBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, ScramSpacing.md)
                    }
                    .background(Color.scramGreen)
                    .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))

                    Button { connection.unpair() } label: {
                        Text("Unpair")
                            .font(.scramBody)
                            .foregroundStyle(Color.scramTextTertiary)
                            .padding(.vertical, ScramSpacing.md)
                            .padding(.horizontal, ScramSpacing.lg)
                    }
                    .background(Color.scramSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
                }

            case .connected:
                Button { connection.disconnect() } label: {
                    Text("Disconnect")
                        .font(.scramHeadline)
                        .foregroundStyle(Color.scramRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ScramSpacing.md)
                }
                .background(Color.scramRedBg)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))

            default:
                Button { connection.disconnect() } label: {
                    HStack(spacing: ScramSpacing.sm) {
                        ProgressView()
                            .tint(Color.scramTextSecondary)
                        Text("Cancel")
                            .font(.scramHeadline)
                            .foregroundStyle(Color.scramTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ScramSpacing.md)
                }
                .background(Color.scramSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
            }
        }
        .padding(ScramSpacing.xxl)
        .frame(maxWidth: .infinity)
        .background(Color.scramSurface)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
    }

    // MARK: - Live Preview

    private var livePreviewSection: some View {
        VStack(spacing: ScramSpacing.sm) {
            SectionHeader(title: "Display Preview")

            Button {
                showLivePreview = true
            } label: {
                HStack(spacing: ScramSpacing.sm) {
                    Image(systemName: "circle.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.scramGreen)
                    Text("Start Live Preview")
                        .font(.scramBody)
                        .foregroundStyle(Color.scramTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.scramTextTertiary)
                }
                .padding(ScramSpacing.lg)
                .background(Color.scramSurface)
                .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
            }
            .fullScreenCover(isPresented: $showLivePreview) {
                DisplayPreviewView(isPresented: $showLivePreview)
            }
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        VStack(spacing: ScramSpacing.sm) {
            SectionHeader(title: "Debug")

            HStack(spacing: ScramSpacing.sm) {
                Button("Ride Simulator") { showSimulator = true }
                    .font(.scramCaption)
                    .foregroundStyle(Color.scramTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ScramSpacing.md)
                    .background(Color.scramSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: ScramRadius.cardSmall))
                    .sheet(isPresented: $showSimulator) {
                        ScenarioPickerView(coordinator: rideCoordinator)
                    }

                Button("Screen Picker") { showScreenPicker = true }
                    .font(.scramCaption)
                    .foregroundStyle(Color.scramTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ScramSpacing.md)
                    .background(Color.scramSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: ScramRadius.cardSmall))
                    .sheet(isPresented: $showScreenPicker) {
                        ScreenPickerView()
                    }
            }

        }
    }
    #endif
}
