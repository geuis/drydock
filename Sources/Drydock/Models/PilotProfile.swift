import Foundation

// A handful of top-level resource128 scalars exposed as typed convenience
// accessors on PilotFile (shipClassIndex, combatRating, credits), alongside
// the equivalent resource129 scalars from PilotUniverseState (isMale,
// strictPlay) and PilotShipIdentity (shipName). These offsets duplicate
// values already present as FieldDefinition entries in the bundled
// FieldSchema.json ("shipClass", "rating", "cash") - that JSON-driven system
// stays the generic/untyped path (PilotFieldValue), while this type gives
// the UI a typed, no-lookup-needed path for the handful of fields it needs
// directly. Both paths read/write the identical bytes.
public enum PilotProfile {
    // Absolute offset 6 = resource128Start (4) + doc offset 0x0002
    // (`short shipClass`). Verified against both real fixtures: Chuck Yeager
    // decodes to 19 (-> ship ID 19 + 128 = 147, "Pirate Carrier" - matches
    // his known ship name "Pirate Carrier 476"), Geuis decodes to 37
    // (-> ship ID 165, "Mod Starbridge").
    public static let shipClassIndexOffset = 6

    // Absolute offset 59730 = the last 4 bytes of resource128 (doc offset
    // 0xe9ae `long rating`). Matches the already-verified "rating"
    // FieldDefinition and the anchor used throughout PilotEscorts.swift's
    // offset derivation. Decodes to plausible combat-rating point totals in
    // both real fixtures (Chuck Yeager 6369, Geuis 1983). Verified.
    public static let combatRatingOffset = 59730

    // Absolute offset 10270 = resource128Start (4) + doc offset 0x281a
    // (`long cash`). Matches the already-verified "cash" FieldDefinition.
    // Decodes to plausible credit totals in both real fixtures. Verified.
    public static let creditsOffset = 10270

    // Absolute offset 8 = resource128Start (4) + doc offset 0x0004
    // (`short cargo[6]`, tons of each standard commodity aboard). Probable:
    // it fits exactly between the verified shipClass (6) and fuel (22)
    // fields, but both sample pilots carry nothing, so no non-zero value
    // has been seen yet.
    public static let tradeCargoOffset = 8
    public static let tradeCargoCount = 6

    // Absolute offset 22, the same bytes as the verified "fuel"
    // FieldDefinition. Typed here so mission checks can read it without
    // the schema.
    public static let fuelOffset = 22

    // MARK: - Decoding

    public static func decodeFuel(from data: Data) -> Int16 {
        let reader = ByteReader(data)
        return (try? reader.int16(at: fuelOffset, byteOrder: .little)) ?? 0
    }

    public static func decodeTradeCargo(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(count: tradeCargoCount, baseOffset: tradeCargoOffset, from: data)
    }

    public static func decodeShipClassIndex(from data: Data) -> Int16 {
        let reader = ByteReader(data)
        return (try? reader.int16(at: shipClassIndexOffset, byteOrder: .little)) ?? 0
    }

    public static func decodeCombatRating(from data: Data) -> Int32 {
        let reader = ByteReader(data)
        return (try? reader.int32(at: combatRatingOffset, byteOrder: .little)) ?? 0
    }

    public static func decodeCredits(from data: Data) -> Int32 {
        let reader = ByteReader(data)
        return (try? reader.int32(at: creditsOffset, byteOrder: .little)) ?? 0
    }

    // MARK: - Writing

    public static func setShipClassIndex(_ value: Int16, in data: inout Data) throws {
        try ByteWriter.writeInt16(value, at: shipClassIndexOffset, byteOrder: .little, into: &data)
    }
}
