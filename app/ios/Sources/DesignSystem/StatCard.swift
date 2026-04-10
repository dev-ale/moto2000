import SwiftUI

struct StatCard: View {
    let value: String
    let label: String
    var valueColor: Color = .scramTextPrimary

    var body: some View {
        VStack(spacing: ScramSpacing.xs) {
            Text(value)
                .font(.scramMetric)
                .foregroundStyle(valueColor)

            Text(label)
                .font(.scramMetricLabel)
                .foregroundStyle(Color.scramTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color.scramSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ScramRadius.cardSmall))
    }
}

#Preview {
    HStack(spacing: ScramSpacing.sm) {
        StatCard(value: "80%", label: "Helligkeit")
        StatCard(value: "Tag", label: "Modus")
        StatCard(value: "v1.2", label: "Firmware")
    }
    .padding()
    .background(Color.scramBackground)
}
