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

        // Create a simple placeholder image (system symbols crash on iOS 26)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120))
        let image = renderer.image { ctx in
            UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
            UIColor(red: 0.92, green: 0.67, blue: 0, alpha: 1).setStroke()
            let circle = CGRect(x: 10, y: 10, width: 100, height: 100)
            ctx.cgContext.setLineWidth(4)
            ctx.cgContext.strokeEllipse(in: circle)
        }
        let item = ASPickerDisplayItem(
            name: "ScramScreen",
            productImage: image,
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
