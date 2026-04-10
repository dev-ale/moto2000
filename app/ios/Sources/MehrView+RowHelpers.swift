import SwiftUI

// MARK: - Row helpers

extension MehrView {
    func settingsRow(
        icon: String,
        title: String,
        titleColor: Color = .scramTextPrimary,
        detail: String? = nil,
        detailColor: Color = .scramTextSecondary,
        chevron: Bool = false
    ) -> some View {
        HStack(spacing: ScramSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(
                    titleColor == .scramRed
                        ? Color.scramRed : Color.scramGreen
                )
                .frame(width: 24)

            Text(title)
                .font(.scramBody)
                .foregroundStyle(titleColor)

            Spacer()

            if let detail {
                Text(detail)
                    .font(.scramCaption)
                    .foregroundStyle(detailColor)
            }

            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.scramTextTertiary)
            }
        }
        .padding(ScramSpacing.lg)
    }

    func settingsToggleRow(
        icon: String,
        title: String,
        onLabel: String,
        offLabel: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: ScramSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.scramGreen)
                .frame(width: 24)

            Text(title)
                .font(.scramBody)
                .foregroundStyle(Color.scramTextPrimary)

            Spacer()

            HStack(spacing: 0) {
                unitButton(offLabel, selected: !isOn.wrappedValue) {
                    isOn.wrappedValue = false
                }
                unitButton(onLabel, selected: isOn.wrappedValue) {
                    isOn.wrappedValue = true
                }
            }
            .background(Color.scramSurfaceElevated)
            .clipShape(
                RoundedRectangle(cornerRadius: ScramRadius.button)
            )
        }
        .padding(ScramSpacing.lg)
    }

    func unitButton(
        _ label: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.scramCaption)
                .foregroundStyle(
                    selected
                        ? Color.scramBackground
                        : Color.scramTextSecondary
                )
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    selected ? Color.scramGreen : Color.clear
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: ScramRadius.button)
                )
        }
    }

    func settingsPickerRow(
        icon: String,
        title: String,
        options: [Int],
        labels: [String],
        selection: Binding<Int>
    ) -> some View {
        HStack(spacing: ScramSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.scramGreen)
                .frame(width: 24)

            Text(title)
                .font(.scramBody)
                .foregroundStyle(Color.scramTextPrimary)

            Spacer()

            Menu {
                ForEach(
                    Array(zip(options, labels)), id: \.0
                ) { value, label in
                    Button(label) {
                        selection.wrappedValue = value
                    }
                }
            } label: {
                HStack(spacing: ScramSpacing.xs) {
                    Text(
                        labels[
                            options.firstIndex(
                                of: selection.wrappedValue
                            ) ?? 1
                        ]
                    )
                    .font(.scramCaption)
                    .foregroundStyle(Color.scramTextSecondary)
                    Image(
                        systemName: "chevron.up.chevron.down"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(Color.scramTextTertiary)
                }
            }
        }
        .padding(ScramSpacing.lg)
    }
}
