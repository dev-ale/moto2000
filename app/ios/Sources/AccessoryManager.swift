import AccessorySetupKit
import CoreBluetooth
import Observation
import SwiftUI

@Observable
@MainActor
final class AccessoryManager {
    private(set) var accessory: ASAccessory?
    private(set) var sessionState: SessionState = .idle

    private var session = ASAccessorySession()

    enum SessionState: Equatable {
        case idle
        case activated
        case pickerVisible
        case paired
        case error(String)
    }

    /// The Bluetooth UUID to connect to via CoreBluetooth after pairing.
    var bluetoothIdentifier: UUID? {
        accessory?.bluetoothIdentifier
    }

    /// Whether the device has been paired via AccessorySetupKit.
    var isPaired: Bool {
        accessory?.state == .authorized
    }

    /// Display name of the paired accessory.
    var deviceName: String {
        accessory?.displayName ?? "ScramScreen"
    }

    func activate() {
        session.activate(on: .main) { [weak self] event in
            self?.handleEvent(event)
        }
    }

    /// Show the Apple-designed accessory picker. User taps the ScramScreen
    /// device and pairing happens automatically — no custom scanning UI needed.
    func showPicker() {
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = CBUUID(
            string: "12345678-1234-5678-1234-56789ABCDEF0"
        )
        descriptor.bluetoothNameSubstring = "ScramScreen"
        descriptor.supportedOptions = .bluetoothPairingLE

        let item = ASPickerDisplayItem(
            name: "ScramScreen",
            productImage: UIImage(systemName: "circle.circle") ?? UIImage(),
            descriptor: descriptor
        )

        session.showPicker(for: [item]) { [weak self] error in
            if let error {
                self?.sessionState = .error(error.localizedDescription)
            }
        }
    }

    func removeAccessory() {
        guard let accessory else { return }
        session.removeAccessory(accessory) { [weak self] _ in
            self?.accessory = nil
            self?.sessionState = .activated
        }
    }

    // MARK: - Event handling

    private func handleEvent(_ event: ASAccessoryEvent) {
        switch event.eventType {
        case .activated:
            sessionState = .activated
            // Check for previously paired accessories
            if let existing = session.accessories.first {
                accessory = existing
                sessionState = .paired
            }

        case .accessoryAdded:
            accessory = event.accessory
            sessionState = .paired

        case .accessoryRemoved:
            accessory = nil
            sessionState = .activated

        case .accessoryChanged:
            accessory = event.accessory

        case .pickerDidPresent:
            sessionState = .pickerVisible

        case .pickerDidDismiss:
            if accessory == nil {
                sessionState = .activated
            }

        case .pickerSetupFailed:
            sessionState = .error(event.error?.localizedDescription ?? "Setup failed")

        default:
            break
        }
    }
}
