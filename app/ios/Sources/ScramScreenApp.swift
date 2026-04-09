import SwiftUI

/// Entry point for the ScramScreen companion app.
///
/// The real dashboard UI, BLE central, and data providers land in later slices.
/// This stub exists so Slice 0 can prove the Tuist + Xcode + CI pipeline builds
/// and tests a running app end to end.
@main
struct ScramScreenApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
