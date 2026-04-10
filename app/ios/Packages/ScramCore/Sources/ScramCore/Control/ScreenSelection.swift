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

    public init(
        screenID: ScreenID,
        displayName: String,
        iconName: String,
        isEnabled: Bool = true
    ) {
        self.screenID = screenID
        self.displayName = displayName
        self.iconName = iconName
        self.isEnabled = isEnabled
    }

    /// Default selections for the screens that already have renderers in
    /// merged slices (Clock, Compass, Speed+Heading, Navigation). New
    /// renderers should append themselves here as their slices land.
    public static let availableScreens: [ScreenSelection] = [
        .init(screenID: .clock,        displayName: "Clock",           iconName: "clock"),
        .init(screenID: .speedHeading, displayName: "Speed + Heading", iconName: "speedometer"),
        .init(screenID: .navigation,   displayName: "Navigation",      iconName: "arrow.triangle.turn.up.right.diamond"),
        .init(screenID: .compass,      displayName: "Compass",         iconName: "location.north.line"),
        .init(screenID: .weather,      displayName: "Weather",         iconName: "cloud.sun"),
        .init(screenID: .tripStats,    displayName: "Trip Stats",      iconName: "chart.bar"),
        .init(screenID: .music,        displayName: "Music",           iconName: "music.note"),
        .init(screenID: .leanAngle,    displayName: "Lean Angle",      iconName: "angle"),
        .init(screenID: .altitude,     displayName: "Altitude",        iconName: "mountain.2"),
        .init(screenID: .fuelEstimate, displayName: "Fuel",            iconName: "fuelpump"),
        .init(screenID: .appointment,  displayName: "Calendar",        iconName: "calendar"),
        .init(screenID: .incomingCall, displayName: "Incoming Call",   iconName: "phone.arrow.down.left", isEnabled: true),
        .init(screenID: .blitzer,      displayName: "Blitzer",         iconName: "exclamationmark.triangle", isEnabled: true),
    ]
}
