import Foundation

// escortClass[64]/fighterClass[64]/escortUpgrade[64]/escortSale[64]/
// escortVoiceMode[64]: the player's current escort/fighter fleet. All five
// live in resource128 AFTER the mission-data region, so they use the
// `absolute = 4 + doc_relative_offset - 96` rule (the real mission-data
// stride is 96 bytes shorter than the doc's nominal stride - see
// MissionSlot.swift for the full derivation of that -96).
//
// Layout derivation/confidence: these five arrays are contiguous
// (escortClass -> fighterClass -> escortUpgrade -> escortSale ->
// escortVoiceMode -> rating), each exactly 64 * 2 = 128 bytes, immediately
// following stelDominated[2048] (see PilotExploration.swift) and
// immediately followed by the already-verified `rating` field. Applying the
// -96 adjustment to escortVoiceMode's doc-rel offset (0xe92e) plus its
// 128-byte span lands EXACTLY on rating's known-good absolute offset
// (59730) - the same anchor that confirmed stelDominated's offset. This is
// the strongest empirical confirmation available short of a live game
// session: decoded against the "Chuck Yeager" bundled fixture (a pilot who
// has actually hired escorts/fighters), escortClass shows -1 (no escort in
// that slot) mixed with values in the documented 0-767 (captured) and
// 1000-1767 (hired) ranges, fighterClass shows -1 mixed with small values
// in the documented 0-767 range, and escortVoiceMode shows only -1/0/1 -
// exactly the three documented values. The "Geuis" fixture, which has no
// hired escorts, decodes to all -1 across all five arrays, consistent with
// an empty fleet. escortUpgrade/escortSale decode to all-zero in both
// fixtures (plausible: neither pilot has an escort currently queued for
// upgrade or sale). Verified confidence for all five offsets.
public enum PilotEscorts {
    public static let slotCount = 64

    public static let escortClassBaseOffset = 59090
    public static let fighterClassBaseOffset = 59218
    public static let escortUpgradeBaseOffset = 59346
    public static let escortSaleBaseOffset = 59474
    public static let escortVoiceModeBaseOffset = 59602

    // MARK: - Decoding

    public static func decodeEscortClass(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(count: slotCount, baseOffset: escortClassBaseOffset, from: data)
    }

    public static func decodeFighterClass(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(count: slotCount, baseOffset: fighterClassBaseOffset, from: data)
    }

    public static func decodeEscortUpgrade(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(count: slotCount, baseOffset: escortUpgradeBaseOffset, from: data)
    }

    public static func decodeEscortSale(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(count: slotCount, baseOffset: escortSaleBaseOffset, from: data)
    }

    public static func decodeEscortVoiceMode(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(count: slotCount, baseOffset: escortVoiceModeBaseOffset, from: data)
    }

    // MARK: - Writing

    public static func setEscortClass(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(value, at: index, count: slotCount, baseOffset: escortClassBaseOffset, in: &data)
    }

    public static func setFighterClass(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(value, at: index, count: slotCount, baseOffset: fighterClassBaseOffset, in: &data)
    }

    public static func setEscortUpgrade(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(value, at: index, count: slotCount, baseOffset: escortUpgradeBaseOffset, in: &data)
    }

    public static func setEscortSale(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(value, at: index, count: slotCount, baseOffset: escortSaleBaseOffset, in: &data)
    }

    public static func setEscortVoiceMode(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(value, at: index, count: slotCount, baseOffset: escortVoiceModeBaseOffset, in: &data)
    }
}
