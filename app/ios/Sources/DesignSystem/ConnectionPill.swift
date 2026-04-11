import SwiftUI

struct ConnectionPill: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.scramGreen : Color.scramRed)
                .frame(width: 7, height: 7)

            Text(connected ? "Connected" : "Disconnected")
                .font(.scramPill)
                .foregroundStyle(connected ? Color.scramGreen : Color.scramRed)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .background(connected ? Color.scramGreenBg : Color.scramRedBg)
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
