import SwiftUI

struct ConnectionPill: View {
    let connected: Bool

    /* The shared `scramGreen` token is actually amber (legacy naming).
     * Use a true green here so the connected pill reads at a glance. */
    private static let trueGreen = Color(red: 0.29, green: 0.83, blue: 0.50)
    private static let trueGreenBg = Color(red: 0.06, green: 0.18, blue: 0.10)

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Self.trueGreen : Color.scramRed)
                .frame(width: 7, height: 7)

            Text(connected ? "Connected" : "Disconnected")
                .font(.scramPill)
                .foregroundStyle(connected ? Self.trueGreen : Color.scramRed)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .background(connected ? Self.trueGreenBg : Color.scramRedBg)
        .clipShape(Capsule())
        .accessibilityLabel(connected ? "Connected" : "Disconnected")
    }
}

#Preview {
    VStack(spacing: 16) {
        ConnectionPill(connected: true)
        ConnectionPill(connected: false)
    }
    .padding()
    .background(Color.scramBackground)
}
