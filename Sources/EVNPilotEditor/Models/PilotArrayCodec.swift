import Foundation

public enum PilotArrayError: Error {
    case indexOutOfRange
    case dataOutOfBounds
}

// Shared bounds-checked helpers for decoding/writing the pilot file's many
// flat repeating arrays (short[] and Boolean[] regions) that don't fit the
// simple scalar FieldSchema system. Generalizes the direct-byte-indexing
// pattern already established in MissionBits.swift so each array-shaped
// field model (PilotInventory, PilotExploration, PilotEscorts,
// PilotUniverseState) doesn't need to hand-roll its own byte loop.
public enum PilotArrayCodec {
    // MARK: - Decoding

    // Never throws: any index whose absolute offset falls outside `data`'s
    // actual bounds is padded with 0 rather than throwing or trapping, since
    // this reads real (possibly-truncated) user save files.
    // Reads the raw buffer in one pass: views decode these arrays on every
    // redraw, and per-element Data subscripting was a measurable cost.
    public static func decodeInt16Array(count: Int, baseOffset: Int, from data: Data) -> [Int16] {
        var result = [Int16](repeating: 0, count: count)

        data.withUnsafeBytes { buffer in
            for index in 0..<count {
                let offset = baseOffset + index * 2
                guard offset >= 0, offset + 2 <= buffer.count else { continue }

                let low = UInt16(buffer[offset])
                let high = UInt16(buffer[offset + 1])
                result[index] = Int16(bitPattern: low | (high << 8))
            }
        }

        return result
    }

    // Mirrors decodeInt16Array, but for 1-byte-per-entry Boolean regions
    // (e.g. stelDominated) - see MissionBits.decodeAll for the same pattern.
    public static func decodeBoolArray(count: Int, baseOffset: Int, from data: Data) -> [Bool] {
        var result = [Bool](repeating: false, count: count)

        data.withUnsafeBytes { buffer in
            for index in 0..<count {
                let offset = baseOffset + index
                guard offset >= 0, offset < buffer.count else { continue }

                result[index] = buffer[offset] != 0
            }
        }

        return result
    }

    // MARK: - Writing

    // Mirrors MissionSlot.setFlag's pattern: bounds-check the logical index
    // before delegating to ByteWriter, which itself bounds-checks the
    // resulting absolute byte range.
    public static func setInt16(_ value: Int16, at index: Int, count: Int, baseOffset: Int, in data: inout Data) throws {
        guard (0..<count).contains(index) else {
            throw PilotArrayError.indexOutOfRange
        }

        let offset = baseOffset + index * 2
        try ByteWriter.writeInt16(value, at: offset, byteOrder: .little, into: &data)
    }

    // Mirrors MissionBits.setBit's pattern for a single-byte Boolean entry.
    public static func setBool(_ value: Bool, at index: Int, count: Int, baseOffset: Int, in data: inout Data) throws {
        guard (0..<count).contains(index) else {
            throw PilotArrayError.indexOutOfRange
        }

        let absoluteIndex = data.startIndex + baseOffset + index

        guard absoluteIndex >= data.startIndex, absoluteIndex < data.endIndex else {
            throw PilotArrayError.dataOutOfBounds
        }

        data[absoluteIndex] = value ? 1 : 0
    }
}
