import BLECentralClient
import EventKit
import ScramCore
import SwiftUI

// swiftlint:disable:next type_body_length
struct MehrView: View {
    @State var connection: ConnectionViewModel

    @AppStorage("scramscreen.unit.speed")
    private var useKmh = true
    @AppStorage("scramscreen.unit.temp")
    var useCelsius = true
    @AppStorage("scramscreen.alert.sound")
    private var alertSounds = true
    @AppStorage("scramscreen.display.brightness")
    private var brightness: Double = 80
    @AppStorage("scramscreen.fuel.tankCapacityLiters")
    private var tankCapacityLiters: Double = 15

    @State private var showUnpairConfirm = false
    @State var ekCalendars: [EKCalendar] = []
    @State private var availableUpdate: FirmwareUpdate?
    @State private var showOTASheet = false
    @State private var showCalendarSheet = false
    @State var weatherText: String?
    @State var weatherIcon: String = "cloud"
    @State var cameraUpdateStatus: String?
    @State var isUpdatingCameras = false

    var body: some View {
        ScrollView {
            VStack(spacing: ScramSpacing.xxl) {
                Text("More")
                    .font(.scramTitle)
                    .foregroundStyle(Color.scramTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, ScramSpacing.xxl)

                // MARK: - Device

                settingsSection("Device") {
                    deviceSection
                }

                // MARK: - Weather

                settingsSection("Weather") {
                    weatherSection
                }

                // MARK: - Display

                settingsSection("Display") {
                    displaySection
                }

                // MARK: - Units

                settingsSection("Units") {
                    unitsSection
                }

                // MARK: - Calendar

                settingsSection("Calendar") {
                    Button { showCalendarSheet = true } label: {
                        let activeCount = ekCalendars.filter {
                            Self.calendarPreferences.isSelected($0.calendarIdentifier)
                        }.count
                        settingsRow(
                            icon: "calendar",
                            title: "Select Calendars",
                            detail: "\(activeCount) active",
                            chevron: true
                        )
                    }
                }

                // MARK: - Maintenance

                settingsSection("Maintenance") {
                    NavigationLink(destination: MaintenanceView()) {
                        settingsRow(icon: "wrench", title: "Service Log", chevron: true)
                    }
                }

                // MARK: - Tank

                settingsSection("Tank") {
                    tankSection
                }

                // MARK: - Speed Cameras

                settingsSection("Speed Cameras") {
                    speedCameraSection
                }

                // MARK: - Alerts

                settingsSection("Notifications") {
                    alertsSection
                }

                // MARK: - About

                settingsSection("Info") {
                    aboutSection
                }
            }
            .padding(.horizontal, ScramSpacing.xl)
            .padding(.bottom, ScramSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scramBackground)
        .onAppear { refreshCalendars() }
        .sheet(isPresented: $showOTASheet) {
            if let update = availableUpdate {
                OTAUpdateView(
                    currentVersion: connection.firmwareVersion,
                    update: update,
                    onStartUpdate: {},
                    sendOTA: { [connection] data in
                        try await connection.sendOTA(data)
                    }
                )
            }
        }
        .sheet(isPresented: $showCalendarSheet) {
            CalendarSelectionSheet(
                calendars: ekCalendars,
                preferences: Self.calendarPreferences
            )
        }
        .task {
            await checkForFirmwareUpdate()
            await fetchWeather()
        }
    }

    // MARK: - Section wrapper

    func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            SectionHeader(title: title)
            VStack(spacing: 1) {
                content()
            }
            .background(Color.scramSurface)
            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.card))
        }
    }

    // MARK: - Device

    private var deviceSection: some View {
        Group {
            if connection.isPaired {
                settingsRow(
                    icon: "circle.circle",
                    title: connection.accessoryManager.deviceName,
                    detail: connection.statusText,
                    detailColor: connection.statusColor
                )

                firmwareRow

                Button { showUnpairConfirm = true } label: {
                    settingsRow(
                        icon: "xmark.circle",
                        title: "Unpair Device",
                        titleColor: .scramRed
                    )
                }
                .alert("Unpair device?", isPresented: $showUnpairConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Unpair", role: .destructive) {
                        connection.unpair()
                    }
                } message: {
                    Text("The display will be unpaired and must be added again.")
                }
            } else {
                Button { connection.showPicker() } label: {
                    settingsRow(
                        icon: "plus.circle",
                        title: "Add Device",
                        titleColor: .scramGreen
                    )
                }
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Group {
            VStack(spacing: ScramSpacing.sm) {
                HStack {
                    Image(systemName: "sun.min")
                        .foregroundStyle(Color.scramTextTertiary)
                    Slider(value: $brightness, in: 10...100, step: 5)
                        .tint(Color.scramGreen)
                        .onChange(of: brightness) { _, newValue in
                            connection.setBrightness(UInt8(newValue))
                        }
                    Image(systemName: "sun.max")
                        .foregroundStyle(Color.scramTextTertiary)
                    Text("\(Int(brightness))%")
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextSecondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .padding(ScramSpacing.lg)
        }
    }

    // MARK: - Units

    private var unitsSection: some View {
        Group {
            settingsToggleRow(
                icon: "speedometer",
                title: "Speed",
                onLabel: "km/h",
                offLabel: "mph",
                isOn: $useKmh
            )

            settingsToggleRow(
                icon: "thermometer.medium",
                title: "Temperature",
                onLabel: "°C",
                offLabel: "°F",
                isOn: $useCelsius
            )
        }
    }

    // MARK: - Tank

    private var tankSection: some View {
        Group {
            settingsPickerRow(
                icon: "fuelpump",
                title: "Tank Capacity",
                options: [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
                labels: ["9 L", "10 L", "11 L", "12 L", "13 L", "14 L", "15 L", "16 L", "17 L", "18 L", "19 L", "20 L"],
                selection: Binding(
                    get: { Int(tankCapacityLiters) },
                    set: { tankCapacityLiters = Double($0) }
                )
            )
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        Group {
            HStack {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.scramGreen)
                    .frame(width: 24)

                Text("Alarm-Ton")
                    .font(.scramBody)
                    .foregroundStyle(Color.scramTextPrimary)

                Spacer()

                Toggle("", isOn: $alertSounds)
                    .labelsHidden()
                    .tint(Color.scramGreen)
            }
            .padding(ScramSpacing.lg)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Group {
            settingsRow(
                icon: "app",
                title: "App Version",
                detail: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? "1.0"
            )

            settingsRow(
                icon: "number",
                title: "Protocol",
                detail: "v\(AppInfo.protocolVersion)"
            )

            settingsRow(
                icon: "doc.text",
                title: "Licenses",
                chevron: true
            )

            settingsRow(
                icon: "envelope",
                title: "Feedback",
                chevron: true
            )
        }
    }

    // MARK: - Firmware row

    private var firmwareRow: some View {
        Group {
            if let update = availableUpdate {
                Button { showOTASheet = true } label: {
                    HStack(spacing: ScramSpacing.md) {
                        Image(systemName: "cpu")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.scramGreen)
                            .frame(width: 24)

                        Text("Firmware")
                            .font(.scramBody)
                            .foregroundStyle(Color.scramTextPrimary)

                        Spacer()

                        Text("v\(update.version.versionString) available")
                            .font(.scramCaption)
                            .foregroundStyle(Color.scramGreen)

                        Circle()
                            .fill(Color.scramGreen)
                            .frame(width: 8, height: 8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.scramTextTertiary)
                    }
                    .padding(ScramSpacing.lg)
                }
            } else {
                settingsRow(
                    icon: "cpu",
                    title: "Firmware",
                    detail: connection.firmwareVersion?.versionString ?? "--"
                )
            }
        }
    }

    // MARK: - OTA check

    private func checkForFirmwareUpdate() async {
        // OTA flow disabled — the firmware row only displays the
        // currently-running version. Re-enable when a working update
        // path is back in place.
        availableUpdate = nil
    }
}
