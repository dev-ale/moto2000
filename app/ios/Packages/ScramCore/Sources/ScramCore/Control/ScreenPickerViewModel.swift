import Foundation
import BLEProtocol

/// SwiftUI-facing view model for the dev-only screen picker. Owns the
/// observable list of screens, the currently active id, and a back-channel
/// to a ``ScreenController`` that turns user actions into BLE writes.
///
/// Marked `@MainActor` (not `actor`) so SwiftUI can read its mutable state
/// directly without `await`. The controller is the only async surface.
///
/// The class is `@Observable` via macros when imported from a SwiftUI
/// target. To keep ScramCore free of SwiftUI imports we expose the
/// observation surface as a plain `ObservableObject` whose properties are
/// `@Published` — this also means the same view model is unit-testable in
/// the ScramCore test target without bringing in SwiftUI.
@MainActor
public final class ScreenPickerViewModel: ObservableObject {
    @Published public private(set) var screens: [ScreenSelection]
    @Published public private(set) var activeScreenID: ScreenID
    @Published public private(set) var lastCommandDescription: String = "—"
    @Published public var brightnessPercent: Double = 80

    private let controller: ScreenController
    private let store: any KeyValueStore

    public init(
        controller: ScreenController,
        store: any KeyValueStore = InMemoryKeyValueStore(),
        initialActive: ScreenID = .clock
    ) {
        self.controller = controller
        self.store = store
        self.activeScreenID = initialActive
        let base = ScreenSelection.availableScreens
        if let prefs = ScreenPreferences.load(from: store) {
            self.screens = prefs.apply(to: base)
        } else {
            self.screens = base
        }
    }

    public func selectScreen(_ id: ScreenID) {
        guard screens.first(where: { $0.screenID == id })?.isEnabled == true else { return }
        activeScreenID = id
        lastCommandDescription = "setActiveScreen(\(id.rawValue))"
        Task { await controller.setActiveScreen(id) }
    }

    public func applyBrightness() {
        let pct = UInt8(max(0, min(100, brightnessPercent.rounded())))
        lastCommandDescription = "setBrightness(\(pct))"
        Task {
            do {
                try await controller.setBrightness(pct)
            } catch {
                await MainActor.run { self.lastCommandDescription = "error: \(error)" }
            }
        }
    }

    public func sleep() {
        lastCommandDescription = "sleep"
        Task { await controller.sleep() }
    }

    public func wake() {
        lastCommandDescription = "wake"
        Task { await controller.wake() }
    }

    public func clearAlertOverlay() {
        lastCommandDescription = "clearAlertOverlay"
        Task { await controller.clearAlertOverlay() }
    }

    /// Toggle a screen's enabled flag and persist.
    public func setEnabled(_ id: ScreenID, enabled: Bool) {
        guard let idx = screens.firstIndex(where: { $0.screenID == id }) else { return }
        screens[idx].isEnabled = enabled
        persist()
    }

    /// Move screens within the picker. `source` / `destination` follow
    /// SwiftUI's `onMove` semantics. We implement the move in plain
    /// Swift to keep ScramCore free of any SwiftUI dependency.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let sortedIndices = source.sorted()
        let moving = sortedIndices.map { screens[$0] }
        // Remove in reverse so earlier indices stay valid.
        for index in sortedIndices.reversed() {
            screens.remove(at: index)
        }
        // Adjust destination by the number of removed items above it.
        let removedAbove = sortedIndices.filter { $0 < destination }.count
        let adjusted = destination - removedAbove
        let clamped = max(0, min(adjusted, screens.count))
        screens.insert(contentsOf: moving, at: clamped)
        persist()
    }

    public func persist() {
        let prefs = ScreenPreferences(
            orderedScreenIDs: screens.map { $0.screenID.rawValue },
            disabledScreenIDs: Set(screens.filter { !$0.isEnabled }.map { $0.screenID.rawValue })
        )
        try? prefs.save(to: store)
    }
}
