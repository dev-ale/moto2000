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
    @AppStorage("scramscreen.display.nightMode")
    private var nightModePreference = NightModePreference.automatisch.rawValue
    @AppStorage("scramscreen.fuel.tankCapacityLiters")
    private var tankCapacityLiters: Double = 15

    @State private var showUnpairConfirm = false
    @State var ekCalendars: [EKCalendar] = []
    @State private var availableUpdate: FirmwareUpdate?
    @State private var showOTASheet = false
    @State private var showCalendarSheet = false
    @State var weatherText: String?
    @State var weatherIcon: String = "cloud"

    var body: some View {
        ScrollView {
            VStack(spacing: ScramSpacing.xxl) {
                Text("Mehr")
                    .font(.scramTitle)
                    .foregroundStyle(Color.scramTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, ScramSpacing.xxl)

                // MARK: - Device

                settingsSection("Geraet") {
                    deviceSection
                }

                // MARK: - Weather

                settingsSection("Wetter") {
                    weatherSection
                }

                // MARK: - Display

                settingsSection("Anzeige") {
                    displaySection
                }

                // MARK: - Units

                settingsSection("Einheiten") {
                    unitsSection
                }

                // MARK: - Calendar

                settingsSection("Kalender") {
                    Button { showCalendarSheet = true } label: {
                        settingsRow(
                            icon: "calendar",
                            title: "Kalender auswaehlen",
                            detail: "\(ekCalendars.filter { Self.calendarPreferences.isSelected($0.calendarIdentifier) }.count) aktiv",
                            chevron: true
                        )
                    }
                }

                // MARK: - Tank

                settingsSection("Tank") {
                    tankSection
                }

                // MARK: - Alerts

                settingsSection("Benachrichtigungen") {
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
                    onStartUpdate: {}
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
                        title: "Geraet entkoppeln",
                        titleColor: .scramRed
                    )
                }
                .alert("Geraet entkoppeln?", isPresented: $showUnpairConfirm) {
                    Button("Abbrechen", role: .cancel) {}
                    Button("Entkoppeln", role: .destructive) {
                        connection.unpair()
                    }
                } message: {
                    Text("Das Display wird entkoppelt und muss erneut hinzugefuegt werden.")
                }
            } else {
                Button { connection.showPicker() } label: {
                    settingsRow(
                        icon: "plus.circle",
                        title: "Geraet hinzufuegen",
                        titleColor: .scramBlue
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
                    Image(systemName: "sun.max")
                        .foregroundStyle(Color.scramTextTertiary)
                    Text("\(Int(brightness))%")
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextSecondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .padding(ScramSpacing.lg)

            nightModeRow
        }
    }

    // MARK: - Units

    private var unitsSection: some View {
        Group {
            settingsToggleRow(
                icon: "speedometer",
                title: "Geschwindigkeit",
                onLabel: "km/h",
                offLabel: "mph",
                isOn: $useKmh
            )

            settingsToggleRow(
                icon: "thermometer.medium",
                title: "Temperatur",
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
                title: "Tankvolumen",
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
                title: "Protokoll",
                detail: "v\(AppInfo.protocolVersion)"
            )

            settingsRow(
                icon: "doc.text",
                title: "Lizenzen",
                chevron: true
            )

            settingsRow(
                icon: "envelope",
                title: "Feedback",
                chevron: true
            )
        }
    }

    // MARK: - Night mode

    private var nightModeRow: some View {
        HStack(spacing: ScramSpacing.md) {
            Image(systemName: "moon.stars")
                .font(.system(size: 16))
                .foregroundStyle(Color.scramGreen)
                .frame(width: 24)

            Text("Nachtmodus")
                .font(.scramBody)
                .foregroundStyle(Color.scramTextPrimary)

            Spacer()

            HStack(spacing: 0) {
                ForEach(NightModePreference.allCases, id: \.rawValue) { pref in
                    unitButton(
                        pref.label,
                        selected: nightModePreference == pref.rawValue
                    ) {
                        nightModePreference = pref.rawValue
                    }
                }
            }
            .background(Color.scramSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: ScramRadius.button))
        }
        .padding(ScramSpacing.lg)
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

                        Text("v\(update.version.versionString) verfuegbar")
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
        guard connection.isPaired else { return }
        let checker = GitHubReleaseChecker()
        let currentVersion = connection.firmwareVersion ?? FirmwareVersion(major: 0, minor: 0, patch: 0)
        do {
            availableUpdate = try await checker.checkForUpdate(currentVersion: currentVersion)
        } catch {
            // Silently ignore — update badge simply won't appear
        }
    }

}
