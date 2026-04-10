import BLEProtocol
import ScramCore
import SwiftUI

struct ScreensView: View {
    @StateObject private var viewModel: ScreenPickerViewModel
    @State private var currentPage: Int = 0
    @State private var showSortSheet = false

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
        NavigationStack {
            VStack(spacing: 0) {
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
                        viewModel.selectScreen(viewModel.screens[newValue].screenID)
                    }
                }

                Spacer()

                // MARK: - Progress bar

                progressBar
                    .padding(.horizontal, ScramSpacing.xl)
                    .padding(.top, ScramSpacing.sm)

                // MARK: - Check toggle

                screenToggle
                    .padding(.top, ScramSpacing.xxl)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.scramBackground)
            .navigationTitle(currentScreenName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sortieren") { showSortSheet = true }
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramGreen)
                }
            }
            .sheet(isPresented: $showSortSheet) {
                ScreenSortView(viewModel: viewModel)
            }
        }
    }

    private var currentScreenName: String {
        guard currentPage < viewModel.screens.count else { return "" }
        return viewModel.screens[currentPage].displayName
    }

    // MARK: - Display preview

    private func displayPreview(for screen: ScreenSelection) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x0A0A0A))
                .frame(width: 290, height: 290)
                .shadow(color: Color.scramGreen.opacity(0.08), radius: 30)
                .shadow(color: .black.opacity(0.6), radius: 20, y: 10)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x2A2A2A), Color(hex: 0x1A1A1A), Color(hex: 0x151515)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 290, height: 290)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: 0x444444), Color(hex: 0x222222), Color(hex: 0x111111)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .frame(width: 290, height: 290)

            Circle()
                .fill(Color(hex: 0x050505))
                .frame(width: 264, height: 264)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x0C0C0C), Color(hex: 0x080808)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 132
                    )
                )
                .frame(width: 258, height: 258)

            if let imageName = screen.previewImageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 252, height: 252)
                    .clipShape(Circle())
            } else {
                Image(systemName: screen.iconName)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.scramGreen)
            }
        }
        .opacity(screen.isEnabled ? 1.0 : 0.35)
    }

    // MARK: - Check toggle

    private var screenToggle: some View {
        let screen = currentPage < viewModel.screens.count
            ? viewModel.screens[currentPage] : nil
        let enabled = screen?.isEnabled ?? false

        return Button {
            if let screen {
                withAnimation(.spring(duration: 0.2)) {
                    viewModel.setEnabled(screen.screenID, enabled: !screen.isEnabled)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } label: {
            HStack(spacing: ScramSpacing.md) {
                checkCircle(enabled: enabled)

                VStack(alignment: .leading, spacing: 2) {
                    Text(enabled ? "Aktiviert" : "Deaktiviert")
                        .font(.scramBody)
                        .foregroundStyle(Color.scramTextPrimary)

                    Text(enabled
                         ? "Screen wird beim Fahren angezeigt"
                         : "Screen wird uebersprungen")
                        .font(.scramCaption)
                        .foregroundStyle(Color.scramTextTertiary)
                }
            }
        }
    }

    private func checkCircle(enabled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(enabled ? Color.scramGreen : Color.clear)
                .frame(width: 32, height: 32)

            if enabled {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.scramBackground)
            } else {
                Circle()
                    .stroke(Color.scramTextDisabled, lineWidth: 2)
                    .frame(width: 32, height: 32)
            }
        }
        .scaleEffect(enabled ? 1.0 : 0.95)
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<viewModel.screens.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == currentPage ? Color.scramGreen : Color.scramBorder)
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
    }
}
