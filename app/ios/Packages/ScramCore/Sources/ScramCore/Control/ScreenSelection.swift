import Foundation
import BLEProtocol

/// One row in the screen picker. A small Sendable value type so the
/// SwiftUI picker can observe a `[ScreenSelection]` from a view model
/// without crossing actor isolation.
public struct ScreenSelection: Equatable, Hashable, Identifiable, Sendable {
    public var id: ScreenID { screenID }
    public let screenID: ScreenID
    /// Human-facing label, e.g. "Speed + Heading".
    public let displayName: String
    /// SF Symbol name for the row's icon.
    public let iconName: String
    /// Whether the user has enabled this screen for switching.
    public var isEnabled: Bool
    /// Asset catalog image name for the screen preview.
    public let previewImageName: String?

    public init(
        screenID: ScreenID,
        displayName: String,
        iconName: String,
        isEnabled: Bool = true,
        previewImageName: String? = nil
    ) {
        self.screenID = screenID
        self.displayName = displayName
        self.iconName = iconName
        self.isEnabled = isEnabled
        self.previewImageName = previewImageName
    }

    /// Default selections for the screens that already have renderers in
    /// merged slices (Clock, Compass, Speed+Heading, Navigation). New
    /// renderers should append themselves here as their slices land.
    public static let availableScreens: [ScreenSelection] = [
        .init(screenID: .clock,        displayName: "Clock",           iconName: "clock",                                  previewImageName: "screen_clock"),
        .init(screenID: .speedHeading, displayName: "Speed + Heading", iconName: "speedometer",                            previewImageName: "screen_speed"),
        .init(screenID: .navigation,   displayName: "Navigation",      iconName: "arrow.triangle.turn.up.right.diamond",   previewImageName: "screen_navigation"),
        .init(screenID: .compass,      displayName: "Compass",         iconName: "location.north.line",                    previewImageName: "screen_compass"),
        .init(screenID: .weather,      displayName: "Weather",         iconName: "cloud.sun",                              previewImageName: "screen_weather"),
        .init(screenID: .tripStats,    displayName: "Trip Stats",      iconName: "chart.bar",                              previewImageName: "screen_trip_stats"),
        .init(screenID: .music,        displayName: "Music",           iconName: "music.note",                             previewImageName: "screen_music"),
        .init(screenID: .leanAngle,    displayName: "Lean Angle",      iconName: "angle",                                  previewImageName: "screen_lean_angle"),
        .init(screenID: .altitude,     displayName: "Altitude",        iconName: "mountain.2",                             previewImageName: "screen_altitude"),
        .init(screenID: .fuelEstimate, displayName: "Fuel",            iconName: "fuelpump",                               previewImageName: "screen_fuel"),
        .init(screenID: .appointment,  displayName: "Calendar",        iconName: "calendar",                               previewImageName: "screen_calendar"),
        .init(screenID: .incomingCall, displayName: "Incoming Call",   iconName: "phone.arrow.down.left", isEnabled: true, previewImageName: "screen_call"),
        .init(screenID: .blitzer,      displayName: "Blitzer",         iconName: "exclamationmark.triangle", isEnabled: true, previewImageName: "screen_blitzer"),
    ]
}
