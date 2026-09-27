import Foundation

// exploration[2048]/legalStatus[2048]: per-system state, resource128 BEFORE
// the mission-data region (`absolute = 4 + doc_relative_offset`, no -96
// adjustment). stelDominated[2048]: per-stellar-object state, resource128
// AFTER the mission-data region (`absolute = 4 + doc_relative_offset - 96`).
//
// Layout derivation/confidence:
// - exploration (doc-rel 0x1a) is the field immediately after the
//   PlayerFileDataStruct header, absolute 30. legalStatus (doc-rel 0x141a)
//   is the field immediately after itemCount. Chaining doc byte-widths
//   field-by-field from exploration through itemCount/legalStatus/weapCount/
//   ammo lands exactly on the already-verified `cash` offset (10270) with
//   zero gap - see PilotInventory.swift for the shared chain math. Decoded
//   `exploration` values against both real bundled pilot files land
//   exclusively in {0, 1, 2} with plausible scattered 1s/2s (visited /
//   visited+landed), exactly matching the documented semantics - verified
//   confidence. `legalStatus` decodes to a plausible mix of small negative
//   and positive values with ~300+ nonzero entries per file (0 = neutral,
//   per the doc) - verified confidence.
// - stelDominated (doc-rel 0xdf2e) is the field immediately after
//   missionBit[10000] ends (0xb81e + 10000 = 0xdf2e exactly), so its offset
//   chains directly off MissionBits.baseOffset (47042) + 10000 = 57042,
//   matching the -96-adjusted arithmetic below. Both real sample files
//   decode this entire 2048-byte region to all-zero (no dominated stellar
//   objects) - a valid Boolean-domain result and unsurprising for typical
//   playthroughs, but weaker positive evidence than seeing a mix of set/
//   unset entries. Given the offset chain itself is airtight (anchored by
//   the already-verified `rating` field 128 bytes later in the very same
///  -96-adjusted region - see PilotEscorts.swift), this is marked verified
//   for the offset, with the caveat that only the all-zero case has been
//   observed in real data.
public enum PilotExploration {
    public static let explorationCount = 2048
    public static let explorationBaseOffset = 30

    public static let legalStatusCount = 2048
    public static let legalStatusBaseOffset = 5150

    public static let stelDominatedCount = 2048
    public static let stelDominatedBaseOffset = 57042

    // MARK: - Decoding

    public static func decodeExploration(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(count: explorationCount, baseOffset: explorationBaseOffset, from: data)
    }

    public static func decodeLegalStatus(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(count: legalStatusCount, baseOffset: legalStatusBaseOffset, from: data)
    }

    public static func decodeStelDominated(from data: Data) -> [Bool] {
        PilotArrayCodec.decodeBoolArray(count: stelDominatedCount, baseOffset: stelDominatedBaseOffset, from: data)
    }

    // MARK: - Writing

    public static func setExploration(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(value, at: index, count: explorationCount, baseOffset: explorationBaseOffset, in: &data)
    }

    public static func setLegalStatus(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(value, at: index, count: legalStatusCount, baseOffset: legalStatusBaseOffset, in: &data)
    }

    public static func setStelDominated(_ value: Bool, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setBool(value, at: index, count: stelDominatedCount, baseOffset: stelDominatedBaseOffset, in: &data)
    }
}
