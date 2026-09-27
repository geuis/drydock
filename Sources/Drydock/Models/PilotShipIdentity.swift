import Foundation

public enum PilotShipIdentityError: Error {
    case emptyName
    case nameTooLong
    case unencodableCharacters
    case dataOutOfBounds
}

// The trailing NUL-terminated string appended after resource129, to EOF.
//
// IMPORTANT naming correction (verified against real pilot files): this is
// the player's SHIP NAME, not a "ship class name" - pilotformat.txt says the
// Windows .plt format works by "concatenating the two resources together,
// prefixing each with their size as a long and appending the ship name at
// the end", and separately states resource129's own resource name "is the
// name of the player's ship". Decoded, it reads "Pirate Carrier 476" for the
// Chuck Yeager fixture (whose ship class decodes to ship ID 147, "Pirate Carrier")
// and "Realis 2" for the Geuis fixture - both plausible player-chosen ship
// names, not class names. The bundled schema's "shipClassName" field
// (offset 86104, non-editable) reads these exact same bytes under a
// misleading id - safe to leave alone since it is read-only and this type's
// own offset is independently derived (resource129Start + resource129's
// documented struct size), not copied from that field definition.
//
// This is the very last thing in the file - nothing else points into it -
// so, unlike every other field in this codebase, writing a new ship name
// changes the file's total length. See PilotFile.setShipName(_:) for how
// that resize is threaded through workingBytes/save().
public enum PilotShipIdentity {
    public static let maxNameLength = 63

    // Absolute offset where the trailing string starts. Confirmed exactly:
    // resource129Start (59738 in both real fixtures) + resource129's
    // documented fixed struct size (26366 bytes) lands on 86104 in both real
    // files, which is byte-for-byte where the trailing string's readable
    // content actually begins (cross-checked against the file's total
    // length in both fixtures: Chuck Yeager's file is exactly 86104 + 19 bytes
    // ("Pirate Carrier 476" + NUL), Geuis's is exactly 86104 + 9 bytes
    // ("Realis 2" + NUL)). Verified.
    public static func tailStart(in data: Data) -> Int {
        PilotUniverseState.resource129Start(in: data) + PilotUniverseState.resource129StructSize
    }

    // MARK: - Decoding

    // Never throws: a short/truncated file simply decodes to "" rather than
    // crashing, matching this codebase's "never crash on a real save file"
    // discipline.
    public static func decodeShipName(from data: Data) -> String {
        let reader = ByteReader(data)
        let start = tailStart(in: data)
        return (try? reader.macRomanCString(at: start, maxLength: 256)) ?? ""
    }

    // MARK: - Writing

    // Replaces everything from tailStart to the current end of `data` with
    // the newly-encoded name plus its NUL terminator. Since the tail is the
    // last thing in the file, this is a resize (not a fixed-span
    // overwrite) - `data`'s count changes by (new tail length - old tail
    // length). Everything before tailStart is left untouched.
    public static func setShipName(_ name: String, in data: inout Data) throws {
        guard !name.isEmpty else {
            throw PilotShipIdentityError.emptyName
        }

        guard let encoded = name.data(using: .macOSRoman) else {
            throw PilotShipIdentityError.unencodableCharacters
        }

        guard encoded.count <= maxNameLength else {
            throw PilotShipIdentityError.nameTooLong
        }

        let start = tailStart(in: data)
        let absoluteStart = data.startIndex + start

        guard absoluteStart >= data.startIndex, absoluteStart <= data.endIndex else {
            throw PilotShipIdentityError.dataOutOfBounds
        }

        var newTail = Data(encoded)
        newTail.append(0x00)

        data.replaceSubrange(absoluteStart..<data.endIndex, with: newTail)
    }
}
