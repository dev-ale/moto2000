import SwiftUI

/// Placeholder root view for the Slice 0 scaffold.
///
/// The real dashboard landing screen (connection state, screen picker, ride controls)
/// is built in Slice 2 and Slice 5.
struct RootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("ScramScreen")
                .font(.largeTitle.weight(.bold))
            Text(AppInfo.tagline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .accessibilityIdentifier("root-view")
    }
}

#Preview {
    RootView()
}
