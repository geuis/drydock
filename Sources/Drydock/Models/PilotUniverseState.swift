import Foundation

public enum PilotUniverseStateError: Error {
    case indexOutOfRange
    case dataOutOfBounds
    case unencodableString
}

// Resource129 fields (the "universe settings" AltPlayerFileDataStruct baked
// into the pilot file right after resource128 / the mission-data region).
//
// Unlike resource128 - which always starts at a fixed absolute offset (4,
// see MissionSlot.Layout.resource128Start) - resource129's start position
// is NOT a fixed absolute offset: the Windows .plt format prefixes each
// resource with its own size as a UInt32, so resource129's start depends on
// resource128's actual stored size. It must therefore be computed per-file
// rather than hardcoded: resource129Start = 4 (resource128's own prefix) +
// resource128Size + 4 (resource129's own size prefix).
//
// Layout derivation/confidence: resource128Size reads 59730 in both real
// bundled pilot files - matching the already-verified `rating` field's own
// known offset exactly - and the resulting resource129Start (59738) plus
// resource129's documented struct size (26366 bytes, per
// AltPlayerFileDataStruct in pilotformat.txt) lands EXACTLY on the
// already-verified `shipClassName` offset (86104) in both files. That's a
// three-way independent confirmation (rating's offset, resource128's
// stated size, and shipClassName's offset all agree) that resource129Start
// = 59738 is correct for real files, and that computing it dynamically from
// the size prefix (rather than hardcoding 59738) is both correct and safer
// for any file whose resource128 size differs.
//
// Per-field confidence notes (see decode function doc comments below for
// detail): stelShipCount, personAlive, seenIntroScreen, priceFlux, and
// rankActive decode to values matching their documented semantics/ranges in
// both real files - verified. personGrudge, stelAnnoyance, junkQty, and the
// ship color fields decode to all-zero in both real files, which is a valid
// but weak (unconfirmed-nonzero) result - probable. disasterTime and
// disasterStellar decode to plausible-looking but not fully doc-matching
// values - see their own comment below - probable.
public enum PilotUniverseState {
    // Falls back to the known-good real-file value (59738) if the size
    // prefix can't be read (e.g. a truncated file), so callers always get a
    // definite offset rather than needing to thread an optional everywhere -
    // mirrors the rest of this codebase's "never crash on a short/corrupt
    // real save file" discipline.
    public static func resource129Start(in data: Data) -> Int {
        let reader = ByteReader(data)
        guard let resource128Size = try? reader.uint32(at: 0, byteOrder: .little) else {
            return 59738
        }
        return 4 + Int(resource128Size) + 4
    }

    // Fixed size of the AltPlayerFileDataStruct (resource129) per
    // pilotformat.txt. Confirmed independently: resource129Start (59738) +
    // this size lands EXACTLY on the already-verified `shipClassName` field's
    // offset (86104, the trailing ship-name string) in both real bundled
    // pilot files - see PilotShipIdentity.swift, which uses this constant to
    // locate that trailing string. Verified.
    public static let resource129StructSize = 26366

    // MARK: - Layout (doc-relative offsets/counts; absolute = resource129Start(in:) + docOffset)

    private enum Layout {
        static let strictPlayFlagDocOffset = 0x0002
        static let genderDocOffset = 0x0004

        static let stelShipCountDocOffset = 0x0006
        static let stelShipCountCount = 2048

        static let personAliveDocOffset = 0x1006
        static let personAliveCount = 1024

        static let personGrudgeDocOffset = 0x1806
        static let personGrudgeCount = 1024

        static let stelAnnoyanceDocOffset = 0x2086
        static let stelAnnoyanceCount = 2048

        static let seenIntroScreenDocOffset = 0x3086

        static let disasterTimeDocOffset = 0x3088
        static let disasterTimeCount = 256

        static let disasterStellarDocOffset = 0x3288
        static let disasterStellarCount = 256

        static let junkQtyDocOffset = 0x3488
        static let junkQtyCount = 128

        // priceFlux[2][2] in the doc; treated here as a flat 4-entry array.
        static let priceFluxDocOffset = 0x3588
        static let priceFluxCount = 4

        static let cronDurationDocOffset = 0x3590
        static let cronDurationCount = 512

        static let cronHoldOffDocOffset = 0x3990
        static let cronHoldOffCount = 512

        static let reinforcementsDocOffset = 0x3d90
        static let reinforcementsCount = 2048

        static let stelDestroyedDocOffset = 0x4d90
        static let stelDestroyedCount = 2048

        static let escortOrdersDocOffset = 0x5d90
        static let escortOrdersCount = 4

        // Pascal string: 1-byte length prefix at this offset, followed by up
        // to 63 chars (doc: `char[63] playerNickname`). Same underlying
        // bytes as the schema-defined "shipName" FieldDefinition (offset
        // 83698 = resource129Start + 0x5d98 in both real fixtures) - that
        // field is misnamed (it is actually the pilot's nickname, not the
        // ship name) and declares an oversized maxLength (69, when the real
        // buffer only spans 64 bytes / 63 chars before shipColorRed begins)
        // but both paths read/write the same leading bytes and therefore
        // agree on the decoded string as long as the name never exceeds 63
        // chars, which this type enforces.
        static let playerNicknameLengthDocOffset = 0x5d98
        static let playerNicknameMaxLength = 63

        static let shipColorRedDocOffset = 0x5dd8
        static let shipColorGreenDocOffset = 0x5dda
        static let shipColorBlueDocOffset = 0x5ddc

        static let rankActiveDocOffset = 0x5dde
        static let rankActiveCount = 128

        static let datePrefixDocOffset = 0x5ede
        static let datePrefixBufferLength = 16

        static let dateSuffixDocOffset = 0x5eee
        static let dateSuffixBufferLength = 16
    }

    // MARK: - Decoding

    // Plausible: values from -1 to 600 with hundreds of nonzero entries in
    // both real files, matching "number of defense ships remaining at each
    // planet". Verified.
    public static func decodeStelShipCount(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.stelShipCountCount,
            baseOffset: resource129Start(in: data) + Layout.stelShipCountDocOffset,
            from: data
        )
    }

    // Plausible: decodes exclusively to 0/1 in both real files, exactly
    // matching the documented "flag to set each 'pers' active or not"
    // Boolean-ish semantics (stored as a short, not a 1-byte Boolean, per
    // the doc's own declared type). Verified.
    public static func decodePersonAlive(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.personAliveCount,
            baseOffset: resource129Start(in: data) + Layout.personAliveDocOffset,
            from: data
        )
    }

    // Decodes to all-zero in both real files. Valid but unconfirmed-nonzero
    // result (neither bundled pilot has given any 'pers' a grudge). Probable.
    public static func decodePersonGrudge(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.personGrudgeCount,
            baseOffset: resource129Start(in: data) + Layout.personGrudgeDocOffset,
            from: data
        )
    }

    // Decodes to all-zero in both real files. Valid but unconfirmed-nonzero
    // result. Probable.
    public static func decodeStelAnnoyance(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.stelAnnoyanceCount,
            baseOffset: resource129Start(in: data) + Layout.stelAnnoyanceDocOffset,
            from: data
        )
    }

    // Reads 1 (true) in both real files - plausible for pilots who have
    // played for a while. Verified.
    public static func decodeSeenIntroScreen(from data: Data) -> Bool {
        let absoluteIndex = data.startIndex + resource129Start(in: data) + Layout.seenIntroScreenDocOffset
        guard absoluteIndex >= data.startIndex, absoluteIndex < data.endIndex else {
            return false
        }
        return data[absoluteIndex] != 0
    }

    // Decodes to small non-negative values (0-49) in both real files, with
    // ~19 nonzero entries each. The doc describes this as "<0 = inactive",
    // but neither real file shows any negative value, so the exact
    // active/inactive sentinel convention is not fully confirmed - the
    // offset itself is high-confidence (see file-level comment), but this
    // specific semantic detail is not, hence Probable rather than Verified.
    public static func decodeDisasterTime(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.disasterTimeCount,
            baseOffset: resource129Start(in: data) + Layout.disasterTimeDocOffset,
            from: data
        )
    }

    // Notably, the first ~19 entries of this array are BYTE-FOR-BYTE
    // IDENTICAL between the two independently-played real pilot files
    // (e.g. [9, 47, 35, 85, 11, ...]), with the rest -1. That is strong
    // evidence this is fixed per-disaster-type reference data (which
    // stellar object each disaster slot is tied to) rather than
    // player-specific state - the same kind of cross-file-identical
    // template-data confirmation used for MissionSlot's untouched mission
    // template fields. Probable (offset is high-confidence, but the exact
    // "reference data vs. live state" interpretation isn't independently
    // confirmed against a third data point).
    public static func decodeDisasterStellar(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.disasterStellarCount,
            baseOffset: resource129Start(in: data) + Layout.disasterStellarDocOffset,
            from: data
        )
    }

    // Decodes to all-zero in both real files (neither pilot is carrying
    // junk cargo). Valid but unconfirmed-nonzero result. Probable.
    public static func decodeJunkQty(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.junkQtyCount,
            baseOffset: resource129Start(in: data) + Layout.junkQtyDocOffset,
            from: data
        )
    }

    // Decodes to plausible small positive percentages/values (~90-115) in
    // both real files, matching "global price fluctuations". Verified.
    public static func decodePriceFlux(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.priceFluxCount,
            baseOffset: resource129Start(in: data) + Layout.priceFluxDocOffset,
            from: data
        )
    }

    // Decode to 0 in both real files - within the documented 0-32 range,
    // but both pilots happening to have never customized ship color (0 is a
    // plausible "unset/default" value) is unconfirmed-nonzero. Probable.
    public static func decodeShipColorRed(from data: Data) -> Int16 {
        decodeSingleInt16(docOffset: Layout.shipColorRedDocOffset, from: data)
    }

    public static func decodeShipColorGreen(from data: Data) -> Int16 {
        decodeSingleInt16(docOffset: Layout.shipColorGreenDocOffset, from: data)
    }

    public static func decodeShipColorBlue(from data: Data) -> Int16 {
        decodeSingleInt16(docOffset: Layout.shipColorBlueDocOffset, from: data)
    }

    // Decodes to mostly-0 with a handful of 1 entries in both real files,
    // plausible for per-faction rank flags. Verified.
    public static func decodeRankActive(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.rankActiveCount,
            baseOffset: resource129Start(in: data) + Layout.rankActiveDocOffset,
            from: data
        )
    }

    // Decodes to 0 (off) in both real files - within the documented 0/1
    // domain, but both pilots happening to have strict play disabled is
    // unconfirmed-nonzero. Probable.
    public static func decodeStrictPlay(from data: Data) -> Bool {
        decodeSingleInt16(docOffset: Layout.strictPlayFlagDocOffset, from: data) != 0
    }

    // Decodes to 1 (male) in both real files, matching the documented
    // "1 = male" semantics and domain. Both pilots share the same value, so
    // this is a weaker (single-value) confirmation than a field showing both
    // 0 and 1 across samples, but the value is plausible. Verified.
    public static func decodeIsMale(from data: Data) -> Bool {
        decodeSingleInt16(docOffset: Layout.genderDocOffset, from: data) != 0
    }

    // Decodes to (almost) all -1 in both real files (511/512 and 512/512
    // nonzero entries, sampled values all -1), consistent with this
    // codebase's established "-1 = inactive/unset" sentinel convention seen
    // elsewhere (escortClass, stelDestroyed). Probable (offset is
    // high-confidence per the struct-size chain; the -1-as-inactive
    // interpretation isn't independently doc-confirmed for this field).
    public static func decodeCronDuration(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.cronDurationCount,
            baseOffset: resource129Start(in: data) + Layout.cronDurationDocOffset,
            from: data
        )
    }

    // Same -1-sentinel pattern as decodeCronDuration - see its comment.
    public static func decodeCronHoldOff(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.cronHoldOffCount,
            baseOffset: resource129Start(in: data) + Layout.cronHoldOffDocOffset,
            from: data
        )
    }

    // Decodes to all-zero in both real files (neither pilot has a system
    // reinforcement timer currently counting down). Valid but
    // unconfirmed-nonzero result. Probable.
    public static func decodeReinforcements(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.reinforcementsCount,
            baseOffset: resource129Start(in: data) + Layout.reinforcementsDocOffset,
            from: data
        )
    }

    // Decodes to all -1 in BOTH real files across all 2048 entries, an exact
    // match for the doc's own stated sentinel ("-1 = alive"). Verified.
    public static func decodeStelDestroyed(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.stelDestroyedCount,
            baseOffset: resource129Start(in: data) + Layout.stelDestroyedDocOffset,
            from: data
        )
    }

    // Decodes to all-zero (formation, the documented 0 case) in both real
    // files - neither pilot has customized escort orders. Valid but
    // unconfirmed-nonzero result. Probable.
    public static func decodeEscortOrders(from data: Data) -> [Int16] {
        PilotArrayCodec.decodeInt16Array(
            count: Layout.escortOrdersCount,
            baseOffset: resource129Start(in: data) + Layout.escortOrdersDocOffset,
            from: data
        )
    }

    // Decodes to "Hawkeye" / "geuis" in the two real files - both are the
    // pilot's actual known nickname (matching the already-verified
    // "shipName" FieldDefinition's decoded value for the Chuck Yeager fixture,
    // "Hawkeye"). Verified.
    public static func decodePlayerNickname(from data: Data) -> String {
        let reader = ByteReader(data)
        let offset = resource129Start(in: data) + Layout.playerNicknameLengthDocOffset
        return (try? reader.pascalString(at: offset, maxLength: Layout.playerNicknameMaxLength)) ?? ""
    }

    // Decodes to an empty string in both real files (an all-zero 16-byte
    // buffer). Valid but unconfirmed-nonempty result. Probable.
    public static func decodeDatePrefix(from data: Data) -> String {
        decodeFixedCString(docOffset: Layout.datePrefixDocOffset, bufferLength: Layout.datePrefixBufferLength, from: data)
    }

    // Decodes to the readable string " NC" in BOTH real files, byte-for-byte
    // identical. Two independently-played pilots agreeing exactly on a
    // "date suffix" string is the same kind of cross-file-identical
    // signature this codebase treats as template/reference data rather than
    // live per-pilot state (see decodeDisasterStellar's comment) - the
    // offset/encoding are confirmed working (clean readable text, no
    // decoding failure), but whether this is genuinely player-editable
    // state is not independently confirmed. Probable.
    public static func decodeDateSuffix(from data: Data) -> String {
        decodeFixedCString(docOffset: Layout.dateSuffixDocOffset, bufferLength: Layout.dateSuffixBufferLength, from: data)
    }

    // MARK: - Writing

    public static func setStelShipCount(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.stelShipCountCount,
            baseOffset: resource129Start(in: data) + Layout.stelShipCountDocOffset,
            in: &data
        )
    }

    public static func setPersonAlive(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.personAliveCount,
            baseOffset: resource129Start(in: data) + Layout.personAliveDocOffset,
            in: &data
        )
    }

    public static func setPersonGrudge(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.personGrudgeCount,
            baseOffset: resource129Start(in: data) + Layout.personGrudgeDocOffset,
            in: &data
        )
    }

    public static func setStelAnnoyance(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.stelAnnoyanceCount,
            baseOffset: resource129Start(in: data) + Layout.stelAnnoyanceDocOffset,
            in: &data
        )
    }

    public static func setSeenIntroScreen(_ value: Bool, in data: inout Data) throws {
        let offset = resource129Start(in: data) + Layout.seenIntroScreenDocOffset
        let absoluteIndex = data.startIndex + offset

        guard absoluteIndex >= data.startIndex, absoluteIndex < data.endIndex else {
            throw PilotUniverseStateError.dataOutOfBounds
        }

        data[absoluteIndex] = value ? 1 : 0
    }

    public static func setDisasterTime(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.disasterTimeCount,
            baseOffset: resource129Start(in: data) + Layout.disasterTimeDocOffset,
            in: &data
        )
    }

    public static func setDisasterStellar(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.disasterStellarCount,
            baseOffset: resource129Start(in: data) + Layout.disasterStellarDocOffset,
            in: &data
        )
    }

    public static func setJunkQty(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.junkQtyCount,
            baseOffset: resource129Start(in: data) + Layout.junkQtyDocOffset,
            in: &data
        )
    }

    public static func setPriceFlux(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.priceFluxCount,
            baseOffset: resource129Start(in: data) + Layout.priceFluxDocOffset,
            in: &data
        )
    }

    public static func setShipColorRed(_ value: Int16, in data: inout Data) throws {
        try setSingleInt16(value, docOffset: Layout.shipColorRedDocOffset, in: &data)
    }

    public static func setShipColorGreen(_ value: Int16, in data: inout Data) throws {
        try setSingleInt16(value, docOffset: Layout.shipColorGreenDocOffset, in: &data)
    }

    public static func setShipColorBlue(_ value: Int16, in data: inout Data) throws {
        try setSingleInt16(value, docOffset: Layout.shipColorBlueDocOffset, in: &data)
    }

    public static func setRankActive(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.rankActiveCount,
            baseOffset: resource129Start(in: data) + Layout.rankActiveDocOffset,
            in: &data
        )
    }

    public static func setStrictPlay(_ value: Bool, in data: inout Data) throws {
        try setSingleInt16(value ? 1 : 0, docOffset: Layout.strictPlayFlagDocOffset, in: &data)
    }

    public static func setIsMale(_ value: Bool, in data: inout Data) throws {
        try setSingleInt16(value ? 1 : 0, docOffset: Layout.genderDocOffset, in: &data)
    }

    public static func setCronDuration(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.cronDurationCount,
            baseOffset: resource129Start(in: data) + Layout.cronDurationDocOffset,
            in: &data
        )
    }

    public static func setCronHoldOff(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.cronHoldOffCount,
            baseOffset: resource129Start(in: data) + Layout.cronHoldOffDocOffset,
            in: &data
        )
    }

    public static func setReinforcements(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.reinforcementsCount,
            baseOffset: resource129Start(in: data) + Layout.reinforcementsDocOffset,
            in: &data
        )
    }

    public static func setStelDestroyed(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.stelDestroyedCount,
            baseOffset: resource129Start(in: data) + Layout.stelDestroyedDocOffset,
            in: &data
        )
    }

    public static func setEscortOrder(_ value: Int16, at index: Int, in data: inout Data) throws {
        try PilotArrayCodec.setInt16(
            value, at: index,
            count: Layout.escortOrdersCount,
            baseOffset: resource129Start(in: data) + Layout.escortOrdersDocOffset,
            in: &data
        )
    }

    public static func setPlayerNickname(_ value: String, in data: inout Data) throws {
        let offset = resource129Start(in: data) + Layout.playerNicknameLengthDocOffset
        try ByteWriter.writePascalString(value, at: offset, maxLength: Layout.playerNicknameMaxLength, into: &data)
    }

    public static func setDatePrefix(_ value: String, in data: inout Data) throws {
        try setFixedCString(value, docOffset: Layout.datePrefixDocOffset, bufferLength: Layout.datePrefixBufferLength, in: &data)
    }

    public static func setDateSuffix(_ value: String, in data: inout Data) throws {
        try setFixedCString(value, docOffset: Layout.dateSuffixDocOffset, bufferLength: Layout.dateSuffixBufferLength, in: &data)
    }

    // MARK: - Private single-value helpers

    private static func decodeSingleInt16(docOffset: Int, from data: Data) -> Int16 {
        let reader = ByteReader(data)
        let offset = resource129Start(in: data) + docOffset
        return (try? reader.int16(at: offset, byteOrder: .little)) ?? 0
    }

    private static func setSingleInt16(_ value: Int16, docOffset: Int, in data: inout Data) throws {
        let offset = resource129Start(in: data) + docOffset
        try ByteWriter.writeInt16(value, at: offset, byteOrder: .little, into: &data)
    }

    // Shared helper for the fixed-size char[N] buffers (datePrefix/
    // dateSuffix): reads up to the first NUL byte or bufferLength, whichever
    // comes first - mirrors ByteReader.cString's own semantics.
    private static func decodeFixedCString(docOffset: Int, bufferLength: Int, from data: Data) -> String {
        let reader = ByteReader(data)
        let offset = resource129Start(in: data) + docOffset
        return (try? reader.cString(at: offset, maxLength: bufferLength)) ?? ""
    }

    // Writes into a fixed bufferLength-byte span, truncating to
    // (bufferLength - 1) bytes to always leave room for a NUL terminator,
    // and zero-filling the remainder - mirrors ByteWriter.writePascalString's
    // own truncate-and-zero-fill approach, adapted for a NUL-terminated
    // buffer rather than a Pascal (length-prefixed) one.
    private static func setFixedCString(_ value: String, docOffset: Int, bufferLength: Int, in data: inout Data) throws {
        let offset = resource129Start(in: data) + docOffset
        let absoluteStart = data.startIndex + offset
        let absoluteEnd = absoluteStart + bufferLength

        guard absoluteStart >= data.startIndex, absoluteEnd <= data.endIndex else {
            throw PilotUniverseStateError.dataOutOfBounds
        }

        // Mac OS Roman, like every other string the game stores.
        guard let fullBytes = value.data(using: .macOSRoman) else {
            throw PilotUniverseStateError.unencodableString
        }

        let maxContentLength = bufferLength - 1
        let truncatedBytes = fullBytes.prefix(maxContentLength)

        var buffer = [UInt8]()
        buffer.reserveCapacity(bufferLength)
        buffer.append(contentsOf: truncatedBytes)
        while buffer.count < bufferLength {
            buffer.append(0x00)
        }

        data.replaceSubrange(absoluteStart..<absoluteEnd, with: buffer)
    }
}
