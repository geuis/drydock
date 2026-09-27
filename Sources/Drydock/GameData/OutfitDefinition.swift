import Foundation

// Decoded EV Nova "oütf" (outfit/equipment) resource - the items purchasable
// via "Outfit Ship" at a planet or station. Field order and meaning are
// documented in the Nova Bible ("The oütf resource" section, lines 1822-2110
// of the converted text), but that document does not state exact byte
// offsets or widths - those were derived empirically against real game data
// and confirmed by matching each item's decoded fields against what its name
// implies (e.g. "Cargo Expansion" decodes to ModType 2/"cargo space" with
// ModVal 10; "Fed Cloaking Device" decodes to ModType 17/"cloaking device"
// with a very high TechLevel and Cost). See the task report for the full
// cross-check.
//
// Every oütf resource in the real game data is exactly 1028 bytes, and this
// decodes the whole thing. Layout, from byte 30 onward (bytes 0-29 are the
// original fixed header: DispWeight/Mass/TechLevel/ModType(1-4)/ModVal(1-4)/
// Max/Flags/Cost):
//
//   30-45   Contribute1, Contribute2, Require1, Require2 - four 4-byte
//           fields forming the two documented 64-bit Contribute/Require
//           flag pairs. Values found in real data look exactly like bit
//           flags (1, 2, 4, 8, 9, 64, 128, 256, 511, 512, and for Require2
//           specifically 0x80000001/0x40000001 - i.e. bit 0 plus an
//           occasional high bit), which is strong confirmation these are
//           raw flag fields rather than text. The Bible documents
//           Contribute before Require and that's the order used here, but
//           the two are structurally identical 32-bit flag words, so which
//           physical field is "Contribute" vs "Require" (as opposed to the
//           reverse) could not be independently verified - noted as the one
//           real ambiguity in this block.
//
//   46      Availability - a fixed 255-byte slot holding a NUL-terminated,
//           MacRoman-encoded control-bit *test* expression (e.g. "b134 &
//           P30", "!b424", "((b279 | b316) ..."). Confirmed NOT
//           Pascal-length-prefixed: the byte(s) immediately before every
//           observed string were checked against the string's actual
//           length and never matched (see task report). It's simply raw
//           text, NUL-padded within the slot; a handful of real resources
//           have stray non-NUL "garbage" bytes after the terminator inside
//           an otherwise-empty slot (leftover from editing in the original
//           dev tool) - reading up to the first NUL correctly ignores them,
//           which is presumably also what the original game engine does.
//   301     OnPurchase - same 255-byte-slot encoding. Real content looks
//           like a control-bit *set* expression per the Bible (e.g. "S731
//           D265 D264 D263 D260 D259 D258 D257"), distinct in shape from
//           Availability's boolean test syntax.
//   556     OnSell - same encoding, third and last of the three 255-byte
//           expression slots. 46 + 255*3 = 811, which lands exactly on
//           ShortName's slot - confirming the slot size.
//
//   811     ShortName - fixed 64-byte slot, NUL-terminated/padded MacRoman
//           text (not Pascal-length-prefixed either, same evidence as
//           above). May contain a literal "\n" (backslash + n, two
//           characters) per the Bible's documented line-break convention -
//           not decoded specially here, left as-is for the view layer.
//   875     LCName - 64-byte slot (811 + 64).
//   939     LCPlural - 64-byte slot (875 + 64). 939 + 64 = 1003, matching
//           where the trailing fixed fields below begin.
//
//   1004    ItemClass (Int16) - 0 in the overwhelming majority of real
//           resources (matches the Bible's "0 or -1 if unused"); one
//           confirmed non-default case, "Dr Ralph's Exploration Map" = 25,
//           a plausible pers-resource classification id.
//   1006    ScanMask (Int16) - 0 for ordinary/legal items; confirmed
//           nonzero (bit flags, e.g. 0x8000, 0x2400, 0xe080) exactly on
//           items whose names mark them as illegal/contraband/faction
//           weapons ("Illegal ...", "Pirate ...", "Rebel ...", "Cheap ...",
//           "... - illegal"), matching the Bible's description precisely.
//   1008    BuyRandom (Int16) - real values are exactly the documented
//           1-100 percent range, plus 0/-1 as likely "always available"
//           sentinels.
//   1010    RequireGovt (Int16) - real values found: -1 (the Bible's "all
//           outfit shops" sentinel), 0, 127, and 128. 128 matches the
//           Bible's documented range start (128 = govt class 0). 127 - one
//           less than that - is overwhelmingly the most common value in
//           real data; read as 128 + (-1), it decodes to "govt class -1"
//           under the Bible's own (RequireGovt - 128) formula, i.e.
//           essentially an "unaffiliated/no particular govt" default
//           distinct from the blanket -1 sentinel. 0 appears on a handful
//           of items (mostly non-purchasable/internal ones) and is treated
//           as a second "unused" sentinel. Not battle-tested beyond this
//           scenario's data but internally consistent with the documented
//           encoding.
//   1012-1027  Confirmed all-zero across every real resource sampled -
//           reserved/padding, not decoded as a field.
public struct OutfitDefinition: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String

    public let dispWeight: Int16
    public let mass: Int16
    public let techLevel: Int16
    public let modType: Int16
    public let modVal: Int16
    public let max: Int16
    public let flags: Int16
    public let cost: UInt32

    // "Alternate" modification slots - the bible notes these exist so an
    // item can have a secondary effect (e.g. a weapon that also slows
    // turning). -1 is the documented "unused" sentinel for ModType2-4.
    public let modType2: Int16
    public let modVal2: Int16
    public let modType3: Int16
    public let modVal3: Int16
    public let modType4: Int16
    public let modVal4: Int16

    // 64-bit Contribute/Require flag pairs - see the Layout doc above for
    // why these are read as raw Int32 flag words rather than text.
    public let contribute1: Int32
    public let contribute2: Int32
    public let require1: Int32
    public let require2: Int32

    // Control-bit expression text. Empty string means "unused" (matches the
    // Bible's "leave blank if unused" for all three).
    public let availability: String
    public let onPurchase: String
    public let onSell: String

    // Display strings.
    public let shortName: String
    public let lcName: String
    public let lcPlural: String

    public let itemClass: Int16
    public let scanMask: Int16
    public let buyRandom: Int16
    public let requireGovt: Int16

    // MARK: - ModType lookup

    // The Nova Bible's documented ModType -> effect table (oütf section).
    // ModVal's meaning depends on which ModType it's paired with - this only
    // labels the ModType number for display; see the Bible for what ModVal
    // means for each one.
    public static let modTypeDescriptions: [Int: String] = [
        1: "Weapon",
        2: "More cargo space",
        3: "Ammunition",
        4: "More shield capacity",
        5: "Faster shield recharge",
        6: "Armor",
        7: "Acceleration booster",
        8: "Speed increase",
        9: "Turn rate change",
        10: "Unused",
        11: "Escape pod",
        12: "Fuel capacity increase",
        13: "Density scanner",
        14: "IFF (colorized radar)",
        15: "Afterburner",
        16: "Map",
        17: "Cloaking device",
        18: "Fuel scoop",
        19: "Auto-refueller",
        20: "Auto-eject",
        21: "Clean legal record",
        22: "Hyperspace speed mod",
        23: "Hyperspace dist mod",
        24: "Interference mod",
        25: "Marines",
        26: "(ignored)",
        27: "Increase maximum (of another item)",
        28: "Murk modifier",
        29: "Faster armor recharge",
        30: "Cloak scanner",
        31: "Mining scoop",
        32: "Multi-jump",
        33: "Jamming Type 1",
        34: "Jamming Type 2",
        35: "Jamming Type 3",
        36: "Jamming Type 4",
        37: "Fast jumping",
        38: "Inertial dampener",
        39: "Ion dissipator",
        40: "Ion absorber",
        41: "Gravity resistance",
        42: "Resist deadly stellars",
        43: "Paint",
        44: "Reinforcement inhibitor",
        45: "Modify max guns",
        46: "Modify max turrets",
        47: "Bomb",
        48: "IFF scrambler",
        49: "Repair system",
        50: "Nonlethal bomb"
    ]

    public static func modTypeDescription(for modType: Int16) -> String {
        modTypeDescriptions[Int(modType)] ?? "Unknown (\(modType))"
    }

    // MARK: - RequireGovt lookup

    // Human-readable label for RequireGovt per the Bible's documented
    // encoding: raw govt class = RequireGovt - 128 (mod 1000, one of four
    // "applies to / applies except" bands). See the Layout doc above for
    // why 127 (govt class -1) is treated as a normal, expected value rather
    // than an edge case.
    public static func requireGovtDescription(for requireGovt: Int16) -> String {
        switch requireGovt {
        case -1:
            return "Applies in all outfit shops"
        case 128...383:
            return "Applies only at govt class \(requireGovt - 128) or its allies"
        case 1128...1383:
            return "Applies only at independent stellars, or govt class \(requireGovt - 1128) or its allies"
        case 2128...2383:
            return "Applies everywhere except govt class \(requireGovt - 2128) or its allies"
        case 3128...3383:
            return "Applies everywhere except independent stellars, or govt class \(requireGovt - 3128) or its allies"
        default:
            return "Govt class \(requireGovt - 128)"
        }
    }

    // MARK: - Layout

    enum Layout {
        static let dispWeightOffset = 0
        static let massOffset = 2
        static let techLevelOffset = 4
        static let modTypeOffset = 6
        static let modValOffset = 8
        static let maxOffset = 10
        static let flagsOffset = 12
        static let costOffset = 14 // 4-byte field, occupies 14-17
        static let modType2Offset = 18
        static let modVal2Offset = 20
        static let modType3Offset = 22
        static let modVal3Offset = 24
        static let modType4Offset = 26
        static let modVal4Offset = 28

        static let contribute1Offset = 30 // 4-byte field, occupies 30-33
        static let contribute2Offset = 34 // 4-byte field, occupies 34-37
        static let require1Offset = 38 // 4-byte field, occupies 38-41
        static let require2Offset = 42 // 4-byte field, occupies 42-45

        // Three fixed-size control-bit-expression string slots, empirically
        // confirmed to be exactly 255 bytes apart (46, 301, 556; the third
        // ends exactly at 811, where the ShortName slot begins).
        static let availabilityOffset = 46
        static let onPurchaseOffset = 301
        static let onSellOffset = 556
        static let expressionSlotSize = 255

        // Three fixed-size display-string slots, empirically confirmed to
        // be exactly 64 bytes apart.
        static let shortNameOffset = 811
        static let lcNameOffset = 875
        static let lcPluralOffset = 939
        static let nameSlotSize = 64

        static let itemClassOffset = 1004
        static let scanMaskOffset = 1006
        static let buyRandomOffset = 1008
        static let requireGovtOffset = 1010

        // Confirmed fixed size for every oütf resource found in the real
        // game data (242 resources, all exactly this size).
        static let expectedSize = 1028
    }

    // MARK: - Decoding

    public static func decodeAll(from library: GameDataLibrary) -> [OutfitDefinition] {
        library.resources(ofType: "oütf").compactMap { decode($0) }
    }

    // Never throws out to the caller - a malformed or unexpectedly-shaped
    // resource is simply skipped rather than crashing the catalog, matching
    // this codebase's defensive-decoding convention (see MissionSlot).
    private static func decode(_ resource: GameResource) -> OutfitDefinition? {
        let reader = ByteReader(resource.data)

        do {
            let dispWeight = try reader.int16(at: Layout.dispWeightOffset, byteOrder: .big)
            let mass = try reader.int16(at: Layout.massOffset, byteOrder: .big)
            let techLevel = try reader.int16(at: Layout.techLevelOffset, byteOrder: .big)
            let modType = try reader.int16(at: Layout.modTypeOffset, byteOrder: .big)
            let modVal = try reader.int16(at: Layout.modValOffset, byteOrder: .big)
            let max = try reader.int16(at: Layout.maxOffset, byteOrder: .big)
            let flags = try reader.int16(at: Layout.flagsOffset, byteOrder: .big)
            let cost = try reader.uint32(at: Layout.costOffset, byteOrder: .big)

            let modType2 = try reader.int16(at: Layout.modType2Offset, byteOrder: .big)
            let modVal2 = try reader.int16(at: Layout.modVal2Offset, byteOrder: .big)
            let modType3 = try reader.int16(at: Layout.modType3Offset, byteOrder: .big)
            let modVal3 = try reader.int16(at: Layout.modVal3Offset, byteOrder: .big)
            let modType4 = try reader.int16(at: Layout.modType4Offset, byteOrder: .big)
            let modVal4 = try reader.int16(at: Layout.modVal4Offset, byteOrder: .big)

            let contribute1 = try reader.int32(at: Layout.contribute1Offset, byteOrder: .big)
            let contribute2 = try reader.int32(at: Layout.contribute2Offset, byteOrder: .big)
            let require1 = try reader.int32(at: Layout.require1Offset, byteOrder: .big)
            let require2 = try reader.int32(at: Layout.require2Offset, byteOrder: .big)

            let availability = try reader.macRomanCString(at: Layout.availabilityOffset, maxLength: Layout.expressionSlotSize)
            let onPurchase = try reader.macRomanCString(at: Layout.onPurchaseOffset, maxLength: Layout.expressionSlotSize)
            let onSell = try reader.macRomanCString(at: Layout.onSellOffset, maxLength: Layout.expressionSlotSize)

            let shortName = try reader.macRomanCString(at: Layout.shortNameOffset, maxLength: Layout.nameSlotSize)
            let lcName = try reader.macRomanCString(at: Layout.lcNameOffset, maxLength: Layout.nameSlotSize)
            let lcPlural = try reader.macRomanCString(at: Layout.lcPluralOffset, maxLength: Layout.nameSlotSize)

            let itemClass = try reader.int16(at: Layout.itemClassOffset, byteOrder: .big)
            let scanMask = try reader.int16(at: Layout.scanMaskOffset, byteOrder: .big)
            let buyRandom = try reader.int16(at: Layout.buyRandomOffset, byteOrder: .big)
            let requireGovt = try reader.int16(at: Layout.requireGovtOffset, byteOrder: .big)

            return OutfitDefinition(
                id: resource.id,
                name: resource.name,
                dispWeight: dispWeight,
                mass: mass,
                techLevel: techLevel,
                modType: modType,
                modVal: modVal,
                max: max,
                flags: flags,
                cost: cost,
                modType2: modType2,
                modVal2: modVal2,
                modType3: modType3,
                modVal3: modVal3,
                modType4: modType4,
                modVal4: modVal4,
                contribute1: contribute1,
                contribute2: contribute2,
                require1: require1,
                require2: require2,
                availability: availability,
                onPurchase: onPurchase,
                onSell: onSell,
                shortName: shortName,
                lcName: lcName,
                lcPlural: lcPlural,
                itemClass: itemClass,
                scanMask: scanMask,
                buyRandom: buyRandom,
                requireGovt: requireGovt
            )
        } catch {
            return nil
        }
    }
}
