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

    /// Whether activation has completed (may fail on simulator).
    var isActivated: Bool {
        sessionState == .activated || sessionState == .paired
    }

    /// Show the Apple-designed accessory picker. User taps the ScramScreen
    /// device and pairing happens automatically — no custom scanning UI needed.
    func showPicker() {
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = CBUUID(
            string: "b6ca8101-b172-4d33-8518-8b1700235ed2"
        )
        descriptor.bluetoothNameSubstring = "ScramScreen"
        descriptor.supportedOptions = .bluetoothPairingLE

        // AccessorySetupKit requires a real raster image — system symbols crash
        // in _validateDiscoveryDescriptor. Use the AppIcon from the asset catalog,
        // falling back to a 1x1 pixel placeholder if unavailable.
        let productImage: UIImage = UIImage(named: "AppIcon") ?? {
            let size = CGSize(width: 1, height: 1)
            UIGraphicsBeginImageContext(size)
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let img = UIGraphicsGetImageFromCurrentImageContext()!   // swiftlint:disable:this force_unwrapping
            UIGraphicsEndImageContext()
            return img
        }()

        let item = ASPickerDisplayItem(
            name: "ScramScreen",
            productImage: productImage,
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

    private func handleEvent(_ event: ASAccessoryEvent) { // swiftlint:disable:this cyclomatic_complexity
        switch event.eventType {
        case .activated:
            sessionState = .activated
            if let existing = session.accessories.first {
                accessory = existing
                sessionState = .paired
            }

        case .invalidated:
            if let err = event.error {
                sessionState = .error(err.localizedDescription)
            } else {
                sessionState = .idle
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
