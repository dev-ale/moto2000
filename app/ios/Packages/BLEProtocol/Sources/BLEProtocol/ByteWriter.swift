import Foundation

/// Accumulates little-endian bytes into a `Data` buffer.
///
/// Intentionally minimal — all appends succeed, no growth strategy beyond
/// `Data`'s built-in behavior.
struct ByteWriter {
    private(set) var data: Data

    init(capacity: Int = 0) {
        data = Data()
        data.reserveCapacity(capacity)
    }

    mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }

    mutating func writeUInt16(_ value: UInt16) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func writeInt16(_ value: Int16) {
        writeUInt16(UInt16(bitPattern: value))
    }

    mutating func writeUInt32(_ value: UInt32) {
        for i in 0..<4 {
            data.append(UInt8(truncatingIfNeeded: value >> (8 * i)))
        }
    }

    mutating func writeInt32(_ value: Int32) {
        writeUInt32(UInt32(bitPattern: value))
    }

    mutating func writeUInt64(_ value: UInt64) {
        for i in 0..<8 {
            data.append(UInt8(truncatingIfNeeded: value >> (8 * i)))
        }
    }

    mutating func writeInt64(_ value: Int64) {
        writeUInt64(UInt64(bitPattern: value))
    }

    mutating func writeBytes(_ bytes: Data) {
        data.append(bytes)
    }

    mutating func writeFixedString(_ value: String, length: Int) throws {
        let utf8 = Array(value.utf8)
        guard utf8.count < length else {
            throw BLEProtocolError.valueOutOfRange(
                field: "string '\(value)' is \(utf8.count) bytes, must be < \(length) to fit terminator"
            )
        }
        data.append(contentsOf: utf8)
        data.append(contentsOf: Array(repeating: UInt8(0), count: length - utf8.count))
    }
}
