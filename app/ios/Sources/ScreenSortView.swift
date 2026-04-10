import ScramCore
import SwiftUI

struct ScreenSortView: View {
    @ObservedObject var viewModel: ScreenPickerViewModel

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.screens) { screen in
                    HStack(spacing: ScramSpacing.md) {
                        // Round preview thumbnail
                        ZStack {
                            Circle()
                                .fill(Color(hex: 0x0A0A0A))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.scramBorder, lineWidth: 1.5)
                                )

                            if let imageName = screen.previewImageName {
                                Image(imageName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: screen.iconName)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.scramGreen)
                            }
                        }
                        .opacity(screen.isEnabled ? 1.0 : 0.35)

                        // Screen name
                        Text(screen.displayName)
                            .font(.scramBody)
                            .foregroundStyle(
                                screen.isEnabled
                                    ? Color.scramTextPrimary
                                    : Color.scramTextDisabled
                            )

                        Spacer()

                        // Enable/disable toggle
                        Button {
                            withAnimation(.spring(duration: 0.2)) {
                                viewModel.setEnabled(screen.screenID, enabled: !screen.isEnabled)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(screen.isEnabled ? Color.scramGreen : Color.clear)
                                    .frame(width: 24, height: 24)

                                if screen.isEnabled {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.scramBackground)
                                } else {
                                    Circle()
                                        .stroke(Color.scramTextDisabled, lineWidth: 1.5)
                                        .frame(width: 24, height: 24)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Color.scramSurface)
                    .listRowSeparatorTint(Color.scramBorder)
                }
                .onMove { source, destination in
                    viewModel.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Color.scramBackground)
            .navigationTitle("Sortieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .foregroundStyle(Color.scramGreen)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
