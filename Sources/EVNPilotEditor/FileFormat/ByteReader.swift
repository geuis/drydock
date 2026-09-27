import Foundation

public enum ByteReaderError: Error {
    case outOfBounds
    case invalidEncoding
}

// Bounds-checked reader over a pilot file's raw bytes. Never traps on
// malformed or out-of-range offsets, since this reads real user save files.
public struct ByteReader {
    public let data: Data

    public init(_ data: Data) {
        self.data = data
    }

    public func int16(at offset: Int, byteOrder: ByteOrder) throws -> Int16 {
        let bytes = try bytes(at: offset, length: 2)
        let b0 = UInt16(bytes[bytes.startIndex])
        let b1 = UInt16(bytes[bytes.startIndex + 1])

        let raw: UInt16
        switch byteOrder {
        case .little:
            raw = b0 | (b1 << 8)
        case .big:
            raw = (b0 << 8) | b1
        }

        return Int16(bitPattern: raw)
    }

    public func int32(at offset: Int, byteOrder: ByteOrder) throws -> Int32 {
        let raw = try uint32(at: offset, byteOrder: byteOrder)
        return Int32(bitPattern: raw)
    }

    // Unsigned counterpart to int32(at:byteOrder:) - needed for fields like
    // file offsets/sizes/counts that are naturally unsigned and shouldn't be
    // reinterpreted as negative via bitPattern.
    public func uint32(at offset: Int, byteOrder: ByteOrder) throws -> UInt32 {
        let bytes = try bytes(at: offset, length: 4)
        let start = bytes.startIndex
        let b0 = UInt32(bytes[start])
        let b1 = UInt32(bytes[start + 1])
        let b2 = UInt32(bytes[start + 2])
        let b3 = UInt32(bytes[start + 3])

        switch byteOrder {
        case .little:
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        case .big:
            return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }
    }

    // Reads a 1-byte length prefix at `offset`, then up to `maxLength` bytes
    // starting at `offset + 1`, decoding min(lengthByte, maxLength) bytes as
    // Mac OS Roman and trimming any trailing embedded nulls. Pilot files come
    // from the classic Mac code base, so accented names use that encoding.
    public func pascalString(at offset: Int, maxLength: Int) throws -> String {
        guard offset >= 0, maxLength >= 0 else {
            throw ByteReaderError.outOfBounds
        }

        let lengthByteData = try bytes(at: offset, length: 1)
        let declaredLength = Int(lengthByteData[lengthByteData.startIndex])
        let effectiveLength = min(declaredLength, maxLength)

        let stringBytes = try bytes(at: offset + 1, length: effectiveLength)
        let trimmed = stringBytes.prefix { $0 != 0x00 }

        guard let decoded = String(data: trimmed, encoding: .macOSRoman) else {
            throw ByteReaderError.invalidEncoding
        }

        return decoded
    }

    // Reads bytes from `offset` up to the first 0x00 byte, `maxLength` bytes,
    // or end of data, whichever comes first, and decodes using Mac OS Roman
    // encoding. Classic Mac / BurgerLib resource formats (e.g. .rez archives)
    // use this encoding for resource names, which may contain accented
    // characters outside plain ASCII/UTF8. Pilot strings share the encoding.
    public func cString(at offset: Int, maxLength: Int) throws -> String {
        guard offset >= 0, offset <= data.count, maxLength >= 0 else {
            throw ByteReaderError.outOfBounds
        }

        let absoluteStart = data.startIndex + offset
        let maxEnd = min(absoluteStart + maxLength, data.endIndex)

        var end = absoluteStart
        while end < maxEnd, data[end] != 0x00 {
            end += 1
        }

        guard absoluteStart <= end else {
            throw ByteReaderError.outOfBounds
        }

        let slice = data[absoluteStart..<end]

        guard let decoded = String(data: slice, encoding: .macOSRoman) else {
            throw ByteReaderError.invalidEncoding
        }

        return decoded
    }

    // Same as cString(at:maxLength:), named for the resource decoders that
    // call out the encoding explicitly.
    public func macRomanCString(at offset: Int, maxLength: Int) throws -> String {
        try cString(at: offset, maxLength: maxLength)
    }

    public func bytes(at offset: Int, length: Int) throws -> Data {
        guard offset >= 0, length >= 0 else {
            throw ByteReaderError.outOfBounds
        }

        let absoluteStart = data.startIndex + offset
        let absoluteEnd = absoluteStart + length

        guard absoluteStart >= data.startIndex, absoluteEnd <= data.endIndex else {
            throw ByteReaderError.outOfBounds
        }

        return data.subdata(in: absoluteStart..<absoluteEnd)
    }
}
