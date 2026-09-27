import Foundation

public enum MissionBitsError: Error {
    case indexOutOfRange
    case dataOutOfBounds
}

// The game's global story/plugin flag bits: missionBit[10000], a flat array
// of individual 1-byte booleans. Distinct from the four per-mission
// completion flags in MissionSlot, which only cover the 16 active mission
// slots - this array covers the game's broader story/plugin progress state.
//
// Layout derivation: missionData[16] (see MissionSlot.Layout) starts at
// absolute offset 0x2962 with a verified real per-slot stride of 2278 bytes;
// missionBit begins immediately after missionData ends:
// 0x2962 + 16*2278 = 47042 (0xB7C2). Confirmed against two real sample files:
// scanning the entire 10,000-byte region found only 0x00/0x01 values present,
// exactly what a real boolean array would show, and the sparse set-bit
// counts (46 and 11 respectively) are plausible for story-progress flags.
public enum MissionBits {
    public static let count = 10000
    public static let baseOffset = 47042

    // Never crashes: if `data` is too short to cover the full missionBit
    // region, missing entries are padded with `false` rather than throwing
    // or trapping, since this reads real user save files.
    public static func decodeAll(from data: Data) -> [Bool] {
        PilotArrayCodec.decodeBoolArray(count: count, baseOffset: baseOffset, from: data)
    }

    // Convenience for the UI's default sparse view: just the indices that
    // are currently set, rather than the full 10,000-entry array. Scans the
    // raw buffer because the Story Flags page calls this on every redraw.
    public static func setIndices(from data: Data) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(128)

        data.withUnsafeBytes { buffer in
            for index in 0..<count {
                let offset = baseOffset + index
                guard offset < buffer.count else { break }

                if buffer[offset] != 0 {
                    result.append(index)
                }
            }
        }

        return result
    }

    public static func isSet(_ index: Int, in data: Data) -> Bool {
        guard (0..<count).contains(index) else { return false }
        let absoluteIndex = data.startIndex + baseOffset + index
        guard absoluteIndex >= data.startIndex, absoluteIndex < data.endIndex else { return false }
        return data[absoluteIndex] != 0
    }

    // Mirrors MissionSlot.setFlag's pattern: bounds-check both the logical
    // index and the resulting absolute byte offset before writing a single
    // byte, throwing rather than crashing on bad input.
    public static func setBit(_ index: Int, to value: Bool, in data: inout Data) throws {
        guard (0..<count).contains(index) else {
            throw MissionBitsError.indexOutOfRange
        }

        let absoluteIndex = data.startIndex + baseOffset + index

        guard absoluteIndex >= data.startIndex, absoluteIndex < data.endIndex else {
            throw MissionBitsError.dataOutOfBounds
        }

        data[absoluteIndex] = value ? 1 : 0
    }
}
