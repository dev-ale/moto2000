import SwiftUI

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.scramOverline)
            .foregroundStyle(Color.scramTextTertiary)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, ScramSpacing.sm)
    }
}
