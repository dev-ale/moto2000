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
        descriptor.bluetoothNameSubstring = "Scram"
        descriptor.supportedOptions = .bluetoothPairingLE

        // AccessorySetupKit requires a real raster image — system symbols crash
        // in _validateDiscoveryDescriptor. Render a simple branded icon.
        let productImage: UIImage = {
            let size = CGSize(width: 120, height: 120)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                // Dark circle background
                UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
                // Amber "S" letter
                let font = UIFont.systemFont(ofSize: 56, weight: .bold)
                let text = "S" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1),
                ]
                let textSize = text.size(withAttributes: attrs)
                let point = CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                )
                text.draw(at: point, withAttributes: attrs)
            }
        }()

        let item = ASPickerDisplayItem(
            name: "ScramScreen",
            productImage: productImage,
            descriptor: descriptor
        )

        print("[ASK] showPicker called, sessionState=\(sessionState)")
        session.showPicker(for: [item]) { [weak self] error in
            if let error {
                print("[ASK] showPicker error: \(error)")
                self?.sessionState = .error(error.localizedDescription)
            } else {
                print("[ASK] showPicker completed without error")
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
        print("[ASK] event: \(event.eventType.rawValue)")
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
