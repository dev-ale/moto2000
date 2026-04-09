import Foundation

/// Constants that define the ScramScreen BLE wire format.
///
/// These values must match `docs/ble-protocol.md`, `protocol/fixtures/generate.py`,
/// and `hardware/firmware/components/ble_protocol/`. Any change here is a wire-format
/// change and requires bumping ``protocolVersion`` and regenerating every fixture.
public enum BLEProtocolConstants {
    /// Current protocol version byte.
    public static let protocolVersion: UInt8 = 0x01

    /// Total size of the common header in bytes.
    public static let headerSize: Int = 8

    /// ScramScreen GATT service UUID.
    public static let serviceUUID = "B6CA8101-B172-4D33-8518-8B1700235ED2"

    /// `screen_data` characteristic — Phone → ESP32, write / write-without-response.
    public static let screenDataCharacteristicUUID = "3AD9D5D0-1D70-4EDF-B2CC-BF1D84DC545B"

    /// `control` characteristic — Phone → ESP32, write.
    public static let controlCharacteristicUUID = "160C1F54-82EC-45E2-8339-1680F16C1A94"

    /// `status` characteristic — ESP32 → Phone, notify/read.
    public static let statusCharacteristicUUID = "B7066D36-D896-4E74-9648-500DF789D969"
}
