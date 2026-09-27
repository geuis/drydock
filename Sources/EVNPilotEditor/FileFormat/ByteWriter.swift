import Foundation

public enum ByteWriterError: Error {
    case outOfBounds
    case valueTooLarge
    case unsupportedFieldType
}

// Bounds-checked writer that only ever overwrites the exact byte range it is
// told to. Never implicitly resizes `data` and never writes past a declared
// field span.
public enum ByteWriter {
    public static func writeInt16(_ value: Int16, at offset: Int, byteOrder: ByteOrder, into data: inout Data) throws {
        try write(bytes: bytes(from: value, byteOrder: byteOrder), at: offset, into: &data)
    }

    public static func writeInt32(_ value: Int32, at offset: Int, byteOrder: ByteOrder, into data: inout Data) throws {
        try write(bytes: bytes(from: value, byteOrder: byteOrder), at: offset, into: &data)
    }

    // Writes a 1-byte length prefix then the ASCII bytes (truncated to
    // maxLength if needed), zero-filling the remainder of the maxLength-sized
    // buffer. Never writes past offset + 1 + maxLength.
    public static func writePascalString(_ value: String, at offset: Int, maxLength: Int, into data: inout Data) throws {
        guard offset >= 0, maxLength >= 0 else {
            throw ByteWriterError.outOfBounds
        }

        let totalSpan = 1 + maxLength
        let absoluteStart = data.startIndex + offset
        let absoluteEnd = absoluteStart + totalSpan

        guard absoluteStart >= data.startIndex, absoluteEnd <= data.endIndex else {
            throw ByteWriterError.outOfBounds
        }

        guard let fullAsciiBytes = value.data(using: .ascii) ?? value.data(using: .utf8) else {
            throw ByteWriterError.valueTooLarge
        }

        let truncatedBytes = fullAsciiBytes.prefix(maxLength)
        let lengthByte = UInt8(truncatedBytes.count)

        var buffer = [UInt8]()
        buffer.reserveCapacity(totalSpan)
        buffer.append(lengthByte)
        buffer.append(contentsOf: truncatedBytes)
        while buffer.count < totalSpan {
            buffer.append(0x00)
        }

        data.replaceSubrange(absoluteStart..<absoluteEnd, with: buffer)
    }

    // MARK: - Private helpers

    private static func bytes(from value: Int16, byteOrder: ByteOrder) -> [UInt8] {
        let raw = UInt16(bitPattern: value)
        let b0 = UInt8(raw & 0xFF)
        let b1 = UInt8((raw >> 8) & 0xFF)

        switch byteOrder {
        case .little:
            return [b0, b1]
        case .big:
            return [b1, b0]
        }
    }

    private static func bytes(from value: Int32, byteOrder: ByteOrder) -> [UInt8] {
        let raw = UInt32(bitPattern: value)
        let b0 = UInt8(raw & 0xFF)
        let b1 = UInt8((raw >> 8) & 0xFF)
        let b2 = UInt8((raw >> 16) & 0xFF)
        let b3 = UInt8((raw >> 24) & 0xFF)

        switch byteOrder {
        case .little:
            return [b0, b1, b2, b3]
        case .big:
            return [b3, b2, b1, b0]
        }
    }

    private static func write(bytes: [UInt8], at offset: Int, into data: inout Data) throws {
        guard offset >= 0 else {
            throw ByteWriterError.outOfBounds
        }

        let absoluteStart = data.startIndex + offset
        let absoluteEnd = absoluteStart + bytes.count

        guard absoluteStart >= data.startIndex, absoluteEnd <= data.endIndex else {
            throw ByteWriterError.outOfBounds
        }

        data.replaceSubrange(absoluteStart..<absoluteEnd, with: bytes)
    }
}
