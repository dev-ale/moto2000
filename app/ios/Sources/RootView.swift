import SwiftUI

/// Placeholder root view for the Slice 0/1/1.5a scaffold.
///
/// The real dashboard landing screen (connection state, screen picker, ride
/// controls) is built in Slice 2 and Slice 5. Until then this view exists
/// only so the app has a scene and the Ride Simulator panel has a host.
struct RootView: View {
    #if DEBUG
    @State private var showSimulator = false
    @State private var showScreenPicker = false
    #endif

    var body: some View {
        VStack(spacing: 16) {
            Text("ScramScreen")
                .font(.largeTitle.weight(.bold))
            Text(AppInfo.tagline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            #if DEBUG
            Button("Ride Simulator") {
                showSimulator = true
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showSimulator) {
                ScenarioPickerView()
            }

            Button("Screen Picker") {
                showScreenPicker = true
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showScreenPicker) {
                ScreenPickerView()
            }
            #endif
        }
        .accessibilityIdentifier("root-view")
    }
}

#Preview {
    RootView()
}
