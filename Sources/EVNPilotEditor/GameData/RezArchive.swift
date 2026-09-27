import Foundation

// Errors that can occur while parsing a BRGR-format .rez archive. These are
// EV Nova's scenario data files (ships, outfits, weapons, missions, ...),
// completely unrelated to the pilot .plt save format handled elsewhere in
// this codebase.
public enum RezArchiveError: Error {
    case invalidSignature
    case unsupportedGroupCount(UInt32)
    case unsupportedGroupType(UInt32)
    case noEntries
    case invalidResourceIndex(Int)
}

// A single resource extracted from a .rez archive: a typed, numbered, named
// blob of raw data (e.g. one ship class definition). `type` is the decoded
// 4-character resource type code (e.g. "shïp", "oütf", "wëap", "mïsn").
public struct GameResource {
    public let type: String
    public let id: Int
    public let name: String
    public let data: Data
}

// Parses EV Nova's BRGR-format .rez archives - the BurgerLib container
// format used to ship scenario data, and the Windows-port replacement for
// the classic Mac OS resource fork. One archive stores many typed, numbered
// resources; this reads the whole archive up front and exposes the parsed
// resources for lookup.
//
// Algorithm adapted from ResForge (MIT licensed), RezFormat.swift:
// https://github.com/andrews05/ResForge
//
// All multi-byte integers are little-endian, except within the resource map
// (reached via the last entry's offset), which is big-endian throughout -
// this matches the real file format and is not a typo.
public final class RezArchive {
    public let resources: [GameResource]

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        self.resources = try RezArchive.parse(data)
    }

    public func resources(ofType type: String) -> [GameResource] {
        resources.filter { $0.type == type }
    }

    // MARK: - Parsing

    private static func parse(_ data: Data) throws -> [GameResource] {
        let reader = ByteReader(data)

        // Root header (12 bytes): signature, numGroups, headerLength (unused -
        // the group header always immediately follows at byte 12).
        let signature = try reader.bytes(at: 0, length: 4)
        guard signature == Data("BRGR".utf8) else {
            throw RezArchiveError.invalidSignature
        }

        let numGroups = try reader.uint32(at: 4, byteOrder: .little)
        guard numGroups == 1 else {
            throw RezArchiveError.unsupportedGroupCount(numGroups)
        }

        // Group header (12 bytes), starts immediately after the root header.
        let groupType = try reader.uint32(at: 12, byteOrder: .little)
        guard groupType == 1 else {
            throw RezArchiveError.unsupportedGroupType(groupType)
        }

        let baseIndex = try reader.uint32(at: 16, byteOrder: .little)
        let numEntries = try reader.uint32(at: 20, byteOrder: .little)
        guard numEntries >= 1 else {
            throw RezArchiveError.noEntries
        }

        // Entry offset table, immediately follows the group header:
        // numEntries entries of 12 bytes each (offset, size, skip).
        let entryTableStart = 24
        var offsets: [Int] = []
        var sizes: [Int] = []
        offsets.reserveCapacity(Int(numEntries))
        sizes.reserveCapacity(Int(numEntries))

        for index in 0..<Int(numEntries) {
            let entryOffset = entryTableStart + index * 12
            let offset = try reader.uint32(at: entryOffset, byteOrder: .little)
            let size = try reader.uint32(at: entryOffset + 4, byteOrder: .little)
            offsets.append(Int(offset))
            sizes.append(Int(size))
        }

        // The last entry's "data" is not a real resource - it's the resource
        // map itself. From here on, everything is read big-endian.
        let mapIndex = Int(numEntries) - 1
        let mapOffset = offsets[mapIndex]

        let typeListRelativeOffset = try reader.uint32(at: mapOffset, byteOrder: .big)
        let numTypes = try reader.uint32(at: mapOffset + 4, byteOrder: .big)
        let typeListOffset = mapOffset + Int(typeListRelativeOffset)

        var result: [GameResource] = []

        for typeIndex in 0..<Int(numTypes) {
            let typeEntryOffset = typeListOffset + typeIndex * 12

            let typeCodeBytes = try reader.bytes(at: typeEntryOffset, length: 4)
            let typeCode = try decodeMacRomanTypeCode(typeCodeBytes)

            let resourceListRelativeOffset = try reader.uint32(at: typeEntryOffset + 4, byteOrder: .big)
            let numResources = try reader.uint32(at: typeEntryOffset + 8, byteOrder: .big)
            let resourceListOffset = mapOffset + Int(resourceListRelativeOffset)

            let typeResources = try parseResourceList(
                reader: reader,
                typeCode: typeCode,
                listOffset: resourceListOffset,
                numResources: numResources,
                baseIndex: baseIndex,
                offsets: offsets,
                sizes: sizes
            )

            result.append(contentsOf: typeResources)
        }

        return result
    }

    // Reads one type's resource list: numResources entries, each
    // rawIndex(4) + skip(4) + id(2) + a fixed 256-byte name field, for a
    // fixed 266-byte stride - NOT the 12-byte stride used by the type list.
    private static func parseResourceList(
        reader: ByteReader,
        typeCode: String,
        listOffset: Int,
        numResources: UInt32,
        baseIndex: UInt32,
        offsets: [Int],
        sizes: [Int]
    ) throws -> [GameResource] {
        var result: [GameResource] = []
        result.reserveCapacity(Int(numResources))

        var cursor = listOffset

        for _ in 0..<Int(numResources) {
            let rawIndex = try reader.uint32(at: cursor, byteOrder: .big)
            // Next 4 bytes are a redundant repeat of the type code - skipped.
            let id = try reader.int16(at: cursor + 8, byteOrder: .big)

            let nameFieldStart = cursor + 10
            let name = try reader.macRomanCString(at: nameFieldStart, maxLength: 256)

            let index = Int(rawIndex) - Int(baseIndex)
            guard index >= 0, index < offsets.count else {
                throw RezArchiveError.invalidResourceIndex(index)
            }

            let resourceData = try reader.bytes(at: offsets[index], length: sizes[index])
            result.append(GameResource(type: typeCode, id: Int(id), name: name, data: resourceData))

            // Always advance by the full fixed-width record, regardless of
            // the name string's actual length - there is padding after the
            // null terminator that must be skipped to stay aligned.
            cursor = nameFieldStart + 256
        }

        return result
    }

    // Resource type codes are a packed 4-character code, decoded via Mac OS
    // Roman (not ASCII/UTF8) - EV Nova's documented codes include several
    // accented characters, e.g. "shïp", "oütf", "wëap", "mïsn".
    private static func decodeMacRomanTypeCode(_ bytes: Data) throws -> String {
        guard let decoded = String(data: bytes, encoding: .macOSRoman) else {
            throw ByteReaderError.invalidEncoding
        }
        return decoded
    }
}
