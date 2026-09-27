import Foundation

public enum MissionSlotError: Error {
    case invalidIndex
    case outOfBounds
}

// One of the 16 concurrent-mission slots in a pilot file's mission chain.
// Decoded directly from raw bytes, NOT through FieldDefinition/FieldSchema -
// that system is for simple scalar fields and does not fit a repeating
// struct with internal sub-fields.
//
// Layout derivation: the classic Mac EV Nova pilot format doc
// (https://andrews05.github.io/evstuff/guides/pilotformat.txt) describes
// MissionObjectives (20 bytes/slot) and MissionData (nominally 2284
// bytes/slot). Empirically, against two real Windows-port .plt sample
// files, the real MissionData stride is exactly 2278 bytes (6 bytes
// shorter). The doc itself explains all 6 of those bytes: it flags THREE
// fields as "(0 bytes in windows .plt format)" -
//   - local 0x22: `short unused` (2 bytes removed)
//   - local 0x37: `Byte unused`  (1 byte removed)
//   - local 0x8e9 (the struct's last field): `Byte unused[3]` (3 bytes removed)
// 2 + 1 + 3 = 6, exactly accounting for 2284 -> 2278. (An earlier hypothesis
// assumed only the first two were documented and guessed the remaining 3
// bytes were undocumented trailing padding - that hypothesis was wrong only
// in that it missed the doc's own third annotation; the doc does fully
// document all 6 removed bytes.) Because the third removed field is the
// very last field in the struct, no other field's local offset needs any
// adjustment beyond the first two rules below.
//
// Every field offset used here was independently re-derived from the doc's
// stated local offset via `adjustedLocalOffset(_:)` and then confirmed
// against real bytes in both sample files (see verification notes in the
// task report - cross-file identical values for untouched template mission
// slots gave very strong confirmation, since two independently-played pilot
// files matching byte-for-byte on unrelated fields is not something a wrong
// offset could produce by chance).
public struct MissionSlot: Identifiable, Equatable, Sendable {
    public let index: Int
    public var isActive: Bool
    public var travelObjComplete: Bool
    public var shipObjComplete: Bool
    public var missionFailed: Bool
    public var missionID: Int?
    public var missionName: String
    public var specialShipName: String
    public var timeLeft: Int16
    public var pay: Int32
    public var cargoType: Int16
    public var cargoQty: Int16
    public var travelStel: Int16
    public var returnStel: Int16

    public var id: Int { index }

    public init(
        index: Int,
        isActive: Bool,
        travelObjComplete: Bool,
        shipObjComplete: Bool,
        missionFailed: Bool,
        missionID: Int?,
        missionName: String,
        specialShipName: String,
        timeLeft: Int16,
        pay: Int32,
        cargoType: Int16,
        cargoQty: Int16,
        travelStel: Int16,
        returnStel: Int16
    ) {
        self.index = index
        self.isActive = isActive
        self.travelObjComplete = travelObjComplete
        self.shipObjComplete = shipObjComplete
        self.missionFailed = missionFailed
        self.missionID = missionID
        self.missionName = missionName
        self.specialShipName = specialShipName
        self.timeLeft = timeLeft
        self.pay = pay
        self.cargoType = cargoType
        self.cargoQty = cargoQty
        self.travelStel = travelStel
        self.returnStel = returnStel
    }

    // Returned for any slot that fails to decode (out-of-bounds/malformed
    // data), rather than throwing - this reads real user save files and
    // must never crash on a short or corrupt one.
    public static func blank(index: Int) -> MissionSlot {
        MissionSlot(
            index: index,
            isActive: false,
            travelObjComplete: false,
            shipObjComplete: false,
            missionFailed: false,
            missionID: nil,
            missionName: "",
            specialShipName: "",
            timeLeft: 0,
            pay: 0,
            cargoType: 0,
            cargoQty: 0,
            travelStel: 0,
            returnStel: 0
        )
    }

    // MARK: - Layout

    enum Layout {
        // resource128 always starts at absolute file offset 4 (right after
        // the leading size UInt32) - see PilotFile/FieldSchema notes.
        static let resource128Start = 4

        // MissionObjectives[16]: fixed 20-byte stride, unaffected by the
        // MissionData padding differences discussed above.
        static let missionObjectivesBase = resource128Start + 0x281e // absolute 0x2822
        static let missionObjectivesStride = 20

        // MissionData[16]: empirically measured 2278-byte real stride
        // (doc's nominal 2284 bytes minus the 6 documented-removed bytes).
        static let missionDataBase = resource128Start + 0x295e // absolute 0x2962
        static let missionDataStride = 2278

        static let slotCount = 16

        // Local (per-slot) offsets below are the doc's stated local offset
        // (its absolute-for-mission-0 offset minus 0x295e) run through
        // `adjustedLocalOffset`, then verified against real bytes.
        static let missionNameLengthLocalOffset = adjustedLocalOffset(0x7e9) // 2022
        static let missionNameMaxLength = 127

        static let specialShipNameLengthLocalOffset = adjustedLocalOffset(0x70) // 109
        static let specialShipNameMaxLength = 63

        // Doc-relative local offsets 0x00 (travelStellar) and 0x04
        // (returnStellar) - both are before the first removed-field marker
        // (0x22), so adjustedLocalOffset would return them unchanged;
        // written as literals here to match the task's own "no adjustment
        // needed" framing.
        static let travelStelLocalOffset = 0x00
        static let returnStelLocalOffset = 0x04

        static let timeLeftLocalOffset = adjustedLocalOffset(0x48) // 69, Int16
        // Stored as the zero-based mïsn resource index, so resource ID 128
        // is stored as 0, 129 as 1, and so on. Verified with the active
        // "Meet With Merrol DockMaster" slot: raw 655 + 128 = mïsn 783.
        static let missionIDLocalOffset = adjustedLocalOffset(0x50) // 77, Int16
        static let payLocalOffset = adjustedLocalOffset(0x24) // 34, Int32
        static let cargoTypeLocalOffset = adjustedLocalOffset(0x12) // 18, Int16 (before both removed markers)
        static let cargoQtyLocalOffset = adjustedLocalOffset(0x14) // 20, Int16

        // -2 for any field at/after local 0x22 (the removed `short unused`),
        // another -1 (so -3 total) for any field at/after local 0x37 (the
        // removed `Byte unused`). Fields at/after local 0x8e9 would need a
        // further -3, but no field this app exposes falls after that point.
        static func adjustedLocalOffset(_ docLocalOffset: Int) -> Int {
            var value = docLocalOffset
            if docLocalOffset >= 0x22 {
                value -= 2
            }
            if docLocalOffset >= 0x37 {
                value -= 1
            }
            return value
        }
    }

    // MARK: - Decoding

    public static func decodeAll(from data: Data) -> [MissionSlot] {
        (0..<Layout.slotCount).map { decode(index: $0, from: data) }
    }

    private static func decode(index: Int, from data: Data) -> MissionSlot {
        let reader = ByteReader(data)
        let objStart = Layout.missionObjectivesBase + index * Layout.missionObjectivesStride
        let dataStart = Layout.missionDataBase + index * Layout.missionDataStride

        do {
            let activeByte = try reader.bytes(at: objStart, length: 1).first ?? 0
            let travelByte = try reader.bytes(at: objStart + 1, length: 1).first ?? 0
            let shipByte = try reader.bytes(at: objStart + 2, length: 1).first ?? 0
            let failedByte = try reader.bytes(at: objStart + 3, length: 1).first ?? 0

            let missionName = try reader.pascalString(
                at: dataStart + Layout.missionNameLengthLocalOffset,
                maxLength: Layout.missionNameMaxLength
            )
            let specialShipName = try reader.pascalString(
                at: dataStart + Layout.specialShipNameLengthLocalOffset,
                maxLength: Layout.specialShipNameMaxLength
            )
            let timeLeft = try reader.int16(at: dataStart + Layout.timeLeftLocalOffset, byteOrder: .little)
            let rawMissionID = try reader.int16(at: dataStart + Layout.missionIDLocalOffset, byteOrder: .little)
            let missionID = rawMissionID >= 0 ? Int(rawMissionID) + 128 : nil
            let pay = try reader.int32(at: dataStart + Layout.payLocalOffset, byteOrder: .little)
            let cargoType = try reader.int16(at: dataStart + Layout.cargoTypeLocalOffset, byteOrder: .little)
            let cargoQty = try reader.int16(at: dataStart + Layout.cargoQtyLocalOffset, byteOrder: .little)
            let travelStel = try reader.int16(at: dataStart + Layout.travelStelLocalOffset, byteOrder: .little)
            let returnStel = try reader.int16(at: dataStart + Layout.returnStelLocalOffset, byteOrder: .little)

            return MissionSlot(
                index: index,
                isActive: activeByte != 0,
                travelObjComplete: travelByte != 0,
                shipObjComplete: shipByte != 0,
                missionFailed: failedByte != 0,
                missionID: missionID,
                missionName: missionName,
                specialShipName: specialShipName,
                timeLeft: timeLeft,
                pay: pay,
                cargoType: cargoType,
                cargoQty: cargoQty,
                travelStel: travelStel,
                returnStel: returnStel
            )
        } catch {
            return .blank(index: index)
        }
    }

    // MARK: - Writing

    // The four MissionObjectives completion flags are single bytes at fixed,
    // high-confidence offsets unaffected by any of the MissionData stride
    // discussion above, so they are safe to expose as editable "flags".
    public static func setFlag(
        _ flag: MissionFlagKind,
        to value: Bool,
        missionIndex: Int,
        in data: inout Data
    ) throws {
        guard (0..<Layout.slotCount).contains(missionIndex) else {
            throw MissionSlotError.invalidIndex
        }

        let objStart = Layout.missionObjectivesBase + missionIndex * Layout.missionObjectivesStride
        let offset = objStart + flag.localOffset
        let absoluteIndex = data.startIndex + offset

        guard absoluteIndex >= data.startIndex, absoluteIndex < data.endIndex else {
            throw MissionSlotError.outOfBounds
        }

        data[absoluteIndex] = value ? 1 : 0
    }

    // `pay` is a plain Int32 at an offset before both removed-field markers,
    // so it needs no adjustment and decodes to plausible reward amounts
    // (verified cross-file for untouched template missions).
    public static func setPay(_ pay: Int32, missionIndex: Int, in data: inout Data) throws {
        guard (0..<Layout.slotCount).contains(missionIndex) else {
            throw MissionSlotError.invalidIndex
        }

        let dataStart = Layout.missionDataBase + missionIndex * Layout.missionDataStride
        let offset = dataStart + Layout.payLocalOffset
        try ByteWriter.writeInt32(pay, at: offset, byteOrder: .little, into: &data)
    }

    // `timeLeft` was already decoded (see decode(index:from:) above); this
    // adds the matching setter, mirroring setPay's pattern exactly.
    public static func setTimeLeft(_ timeLeft: Int16, missionIndex: Int, in data: inout Data) throws {
        guard (0..<Layout.slotCount).contains(missionIndex) else {
            throw MissionSlotError.invalidIndex
        }

        let dataStart = Layout.missionDataBase + missionIndex * Layout.missionDataStride
        let offset = dataStart + Layout.timeLeftLocalOffset
        try ByteWriter.writeInt16(timeLeft, at: offset, byteOrder: .little, into: &data)
    }
}

public enum MissionFlagKind: String, CaseIterable, Sendable {
    case isActive
    case travelObjComplete
    case shipObjComplete
    case missionFailed

    // Local offset within a single 20-byte MissionObjectives entry.
    var localOffset: Int {
        switch self {
        case .isActive: return 0
        case .travelObjComplete: return 1
        case .shipObjComplete: return 2
        case .missionFailed: return 3
        }
    }

    public var displayName: String {
        switch self {
        case .isActive: return "Active"
        case .travelObjComplete: return "Travel Objective Complete"
        case .shipObjComplete: return "Ship Objective Complete"
        case .missionFailed: return "Mission Failed"
        }
    }
}
