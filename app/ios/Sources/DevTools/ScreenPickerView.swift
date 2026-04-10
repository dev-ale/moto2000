#if DEBUG
import BLEProtocol
import ScramCore
import SwiftUI

/// Debug-only panel for switching the active dashboard screen, tweaking
/// brightness, and triggering sleep / wake / clear-overlay commands.
///
/// Visible only in Debug builds — wrapped in `#if DEBUG` at the top of the
/// file so it cannot leak into Release. Presented as a sheet from
/// ``RootView``.
///
/// All real logic lives in ``ScreenPickerViewModel`` from ScramCore so the
/// view stays trivially thin and the behaviour is exercised by unit tests
/// without needing SwiftUI.
struct ScreenPickerView: View {
    @StateObject private var viewModel: ScreenPickerViewModel

    init() {
        let controller = ScreenController()
        _viewModel = StateObject(
            wrappedValue: ScreenPickerViewModel(
                controller: controller,
                store: UserDefaults.standard
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Active screen") {
                    ForEach(viewModel.screens) { selection in
                        Button {
                            viewModel.selectScreen(selection.screenID)
                        } label: {
                            HStack {
                                Image(systemName: selection.iconName)
                                Text(selection.displayName)
                                Spacer()
                                if viewModel.activeScreenID == selection.screenID {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { selection.isEnabled },
                                        set: { viewModel.setEnabled(selection.screenID, enabled: $0) }
                                    )
                                )
                                .labelsHidden()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!selection.isEnabled)
                    }
                    .onMove { source, destination in
                        viewModel.move(fromOffsets: source, toOffset: destination)
                    }
                }

                Section("Brightness") {
                    Slider(value: $viewModel.brightnessPercent, in: 0...100, step: 1)
                    HStack {
                        Text("\(Int(viewModel.brightnessPercent))%")
                            .monospacedDigit()
                        Spacer()
                        Button("Apply") { viewModel.applyBrightness() }
                    }
                }

                Section("Power") {
                    Button("Sleep") { viewModel.sleep() }
                    Button("Wake")  { viewModel.wake() }
                    Button("Clear Alert Overlay") { viewModel.clearAlertOverlay() }
                }

                Section("Last command") {
                    Text(viewModel.lastCommandDescription)
                        .font(.footnote)
                        .monospaced()
                }
            }
            .navigationTitle("Screen Picker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditButton()
            }
        }
    }
}

#Preview {
    ScreenPickerView()
}
#endif
