import Foundation

/// Errors raised by the BLE protocol codec.
///
/// Every case corresponds to a specific wire-format violation described in
/// `docs/ble-protocol.md` and is exercised by a fixture under
/// `protocol/fixtures/invalid/`.
public enum BLEProtocolError: Error, Equatable, Sendable {
    /// Buffer is shorter than the 8-byte header.
    case truncatedHeader
    /// Protocol version byte is not ``BLEProtocolConstants/protocolVersion``.
    case unsupportedVersion(UInt8)
    /// Reserved header byte is non-zero.
    case invalidReserved
    /// Screen ID is not in the spec.
    case unknownScreenId(UInt8)
    /// `data_length` exceeds the remaining buffer.
    case truncatedBody(declared: Int, available: Int)
    /// Body length does not match the expected length for the screen.
    case bodyLengthMismatch(screen: ScreenID, expected: Int, actual: Int)
    /// Reserved flag bits are set.
    case reservedFlagsSet
    /// A fixed string field is not terminated by a zero byte.
    case unterminatedString
    /// A value in the body is outside its documented range.
    case valueOutOfRange(field: String)
    /// A reserved body byte is non-zero.
    case nonZeroBodyReserved(field: String)
    /// Control command byte is not a known ``ControlCommand`` value.
    case unknownCommand(UInt8)
    /// A control command's value bytes are outside the documented range.
    case invalidCommandValue(field: String)
}
