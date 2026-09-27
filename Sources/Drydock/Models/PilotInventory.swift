import Foundation

// itemCount[512]/weapCount[256]/ammo[256]: how many of each outfit item,
// weapon, and weapon's ammo the pilot currently owns. All three live in
// resource128 BEFORE the mission-data region, so they use the simple
// `absolute = 4 + doc_relative_offset` rule (no -96 adjustment needed) - see
// pilotformat.txt's PlayerFileDataStruct layout.
//
// Layout derivation/confidence: these three fields sit contiguously between
// `exploration` (doc-rel 0x1a) and the already-verified `cash` field
// (doc-rel 0x281a, confirmed absolute 10270). Chaining the doc's own byte
// widths field-by-field from exploration's start (absolute 30) through
// itemCount -> legalStatus -> weapCount -> ammo lands EXACTLY on cash's
// known-good absolute offset with zero gap, which is strong independent
// confirmation of all three offsets below (see PilotExploration.swift for
// the exploration/legalStatus half of this same chain). Decoded values
// against both real bundled pilot files are small, plausible counts (e.g.
// itemCount/ammo mostly 0 with a handful of nonzero entries in the low
// hundreds; weapCount mostly 0 with a handful of small nonzero entries) -
// verified confidence.
public enum PilotInventory {
    public static let itemCountCount = 512
    public static let itemCountBaseOffset = 4126

    public static let weapCountCount = 256
    public static let weapCountBaseOffset = 9246

    public static let ammoCount = 256
    public static let ammoBaseOffset = 9758

    // MARK: - Decoding

    public static func decodeItemCount(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(count: itemCountCount, baseOffset: itemCountBaseOffset, from: data)
    }

    public static func decodeWeapCount(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(count: weapCountCount, baseOffset: weapCountBaseOffset, from: data)
    }

    public static func decodeAmmo(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(count: ammoCount, baseOffset: ammoBaseOffset, from: data)
    }

    // MARK: - Writing

    public static func setItemCount(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(value, at: index, count: itemCountCount, baseOffset: itemCountBaseOffset, in: &data)
    }

    public static func setWeapCount(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(value, at: index, count: weapCountCount, baseOffset: weapCountBaseOffset, in: &data)
    }

    public static func setAmmo(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(value, at: index, count: ammoCount, baseOffset: ammoBaseOffset, in: &data)
    }

    // MARK: - Stock loadout

    // Mirrors what buying the ship gives you: its default weapon slots (with
    // ammo) and default outfit slots, added on top of what's owned. Counts
    // are re-read before every addition, because a ship can list the same
    // weapon or outfit in more than one slot.
    public static func addStockLoadout(of ship: ShipDefinition, in data: inout Data) throws {
        for slot in ship.weapType.indices {
            let index: Int = Int(ship.weapType[slot]) - 128
            let count: Int16 = slot < ship.weapCount.count ? ship.weapCount[slot] : 0
            let ammoLoad: Int16 = slot < ship.ammoLoad.count ? ship.ammoLoad[slot] : 0

            guard (0..<weapCountCount).contains(index), count > 0 else { continue }

            let ownedWeapons: [Int16] = decodeWeapCount(from: data)
            try setWeapCount(clampedSum(ownedWeapons[index], count), at: index, in: &data)

            if ammoLoad > 0 {
                let ownedAmmo: [Int16] = decodeAmmo(from: data)
                try setAmmo(clampedSum(ownedAmmo[index], ammoLoad), at: index, in: &data)
            }
        }

        let itemGroups: [([Int16], [Int16])] = [
            (ship.defaultItems, ship.itemCount),
            (ship.defaultItems2, ship.itemCount2)
        ]

        for (itemIDs, itemCounts) in itemGroups {
            for slot in itemIDs.indices {
                let index: Int = Int(itemIDs[slot]) - 128
                let count: Int16 = slot < itemCounts.count ? itemCounts[slot] : 0

                guard (0..<itemCountCount).contains(index), count > 0 else { continue }

                let ownedItems: [Int16] = decodeItemCount(from: data)
                try setItemCount(clampedSum(ownedItems[index], count), at: index, in: &data)
            }
        }
    }

    // Negative counts are treated as none, and the total stops at the
    // largest value the file can hold.
    static func clampedSum(_ first: Int16, _ second: Int16) -> Int16 {
        let total: Int = Int(max(first, 0)) + Int(second)
        return Int16(min(total, Int(Int16.max)))
    }
}
