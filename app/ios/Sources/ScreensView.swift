import BLEProtocol
import ScramCore
import SwiftUI

struct ScreensView: View {
    @StateObject private var viewModel: ScreenPickerViewModel
    @State private var currentPage: Int = 0

    init() {
        let controller = ScreenController()
        _viewModel = StateObject(
            wrappedValue: ScreenPickerViewModel(
                controller: controller,
                store: UserDefaults.standard,
                initialActive: .speedHeading
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Screens")
                .font(.scramTitle)
                .foregroundStyle(Color.scramTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ScramSpacing.xl)
                .padding(.top, ScramSpacing.xxl)
                .padding(.bottom, ScramSpacing.lg)

            Spacer()

            // MARK: - Display preview carousel

            TabView(selection: $currentPage) {
                ForEach(Array(viewModel.screens.enumerated()), id: \.element.id) { index, screen in
                    displayPreview(for: screen)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 340)
            .onChange(of: currentPage) { _, newValue in
                if newValue < viewModel.screens.count {
                    let screen = viewModel.screens[newValue]
                    viewModel.selectScreen(screen.screenID)
                }
            }

            // MARK: - Page dots

            pageDots
                .padding(.top, ScramSpacing.lg)

            Spacer()

            // MARK: - Screen name + check toggle

            screenToggle
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scramBackground)
    }

    // MARK: - Display preview

    private func displayPreview(for screen: ScreenSelection) -> some View {
        ZStack {
            Circle()
                .stroke(Color.scramBorder, lineWidth: 3)
                .frame(width: 280, height: 280)

            Circle()
                .fill(Color(hex: 0x0A0A0A))
                .frame(width: 274, height: 274)

            VStack(spacing: ScramSpacing.md) {
                Image(systemName: screen.iconName)
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Color.scramGreen)

                Text(screen.displayName)
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramTextSecondary)
            }
        }
        .opacity(screen.isEnabled ? 1.0 : 0.35)
    }

    // MARK: - Page dots

    private var pageDots: some View {
        HStack(spacing: ScramSpacing.xs) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(currentPage > 0 ? Color.scramTextTertiary : Color.scramBorderSubtle)

            ForEach(0..<viewModel.screens.count, id: \.self) { index in
                Circle()
                    .fill(dotColor(at: index))
                    .frame(width: 6, height: 6)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    currentPage < viewModel.screens.count - 1
                        ? Color.scramTextTertiary : Color.scramBorderSubtle
                )
        }
    }

    private func dotColor(at index: Int) -> Color {
        if index == currentPage {
            let screen = viewModel.screens[index]
            return screen.isEnabled ? Color.scramGreen : Color.scramTextTertiary
        }
        return Color.scramBorderSubtle
    }

    // MARK: - Screen toggle

    private var screenToggle: some View {
        let screen = currentPage < viewModel.screens.count
            ? viewModel.screens[currentPage] : nil

        return Button {
            if let screen {
                withAnimation(.spring(duration: 0.2)) {
                    viewModel.setEnabled(screen.screenID, enabled: !screen.isEnabled)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } label: {
            HStack(spacing: ScramSpacing.md) {
                checkCircle(enabled: screen?.isEnabled ?? false)

                Text(screen?.displayName ?? "")
                    .font(.scramHeadline)
                    .foregroundStyle(Color.scramTextPrimary)
            }
        }
    }

    private func checkCircle(enabled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(enabled ? Color.scramGreen : Color.clear)
                .frame(width: 28, height: 28)

            if enabled {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.scramBackground)
            } else {
                Circle()
                    .stroke(Color.scramTextDisabled, lineWidth: 2)
                    .frame(width: 28, height: 28)
            }
        }
        .scaleEffect(enabled ? 1.0 : 0.95)
    }
}
