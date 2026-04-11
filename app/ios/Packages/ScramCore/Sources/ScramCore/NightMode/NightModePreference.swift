import Foundation

/// User preference for night mode behaviour.
///
/// Stored in `UserDefaults` via `@AppStorage` using the raw `String`
/// value so the setting survives app updates without migration.
public enum NightModePreference: String, Sendable, CaseIterable {
    /// Use sunrise/sunset (and lux when available) to decide automatically.
    case automatisch
    /// Always use day mode — ``NightModeService/isNightMode`` is forced
    /// to `false`.
    case tag
    /// Always use night mode — ``NightModeService/isNightMode`` is forced
    /// to `true`.
    case nacht

    /// Localised display label for the UI.
    public var label: String {
        switch self {
        case .automatisch: return "Auto"
        case .tag: return "Day"
        case .nacht: return "Night"
        }
    }
}
