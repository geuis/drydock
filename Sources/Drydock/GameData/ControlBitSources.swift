import Foundation

// Lightweight decoders for scenario resource types whose only content
// relevant to StoryFlagCatalog is one or more control-bit test/set
// expression fields (Nova Bible: "A quick word about control bits and
// scripting in EV Nova", lines 97-226 of the converted text). These are NOT
// full decoders of their resource type the way OutfitDefinition/
// ShipDefinition/MissionDefinition are - only the id/name/expression-string
// fields needed to feed StoryFlagCatalog are extracted.
//
// Every offset below was found the same way the existing decoders found
// theirs: scan every byte offset of every real resource of that type for a
// fixed-width, NUL-terminated MacRoman slot whose content, when non-empty,
// parses as the Bible's documented control-bit expression syntax (letters,
// digits, spaces, & | ! ( ) ^); then cross-check the slot boundary against
// the Bible's documented field order (the slot should start exactly where
// the preceding documented fields' byte widths sum to). Every resource type
// here happens to use the same 255-byte expression slot size already
// established by OutfitDefinition/ShipDefinition/MissionDefinition.
//
// The full Nova Bible survey (grep -n -i "control bit" over the converted
// text) turned up every resource type with a control-bit test/set field:
// chär, crön, dësc (a different, embedded {bXXX "a" "b"} text-substitution
// mechanism, not a dedicated field - out of scope here), flët, jünk, mïsn
// (already covered by MissionDefinition), nëbu, öops, oütf (already
// covered), përs, shïp (already covered), and spöb/sÿst. gövt and ränk were
// also checked (per the task's suggestion to skim them) and confirmed to
// have NO control-bit expression field of their own: gövt only has
// Contribute/Require 64-bit flag pairs (like oütf), and ränk is activated
// entirely from OTHER resources' set expressions (the Kxxx/Lxxx operators),
// never referencing a control bit from within the ränk resource itself.
//
// chär and nëbu are documented to have expression fields (chär's OnStart,
// nëbu's ActiveOn/OnExplore) but are deliberately NOT decoded below: this
// scenario's data ships exactly one chär resource and only four nëbu
// resources, and every one of them has an empty/all-zero value in the
// region where the field should live - there is no non-empty real content to
// confirm an offset against, unlike every type below. Header-field-width
// arithmetic from the Bible's documented field order is suggestive (e.g.
// chär's OnStart would land at offset 50) but this codebase's convention is
// to only ship an offset that's been confirmed against real data, so these
// are left out rather than guessed. See the task report for the full
// reasoning.

// MARK: - Timed Event (crön)

// Nova Bible, "The crön resource" (lines 598-716 of the converted text).
// EnableOn/OnStart/OnEnd offsets confirmed against all 125 real crön
// resources: every resource decodes a valid (in-bounds, NUL-terminated,
// correctly-encoded) string at each offset, and 102-121 of the 125 have
// real non-empty content that parses as the documented test/set syntax
// (e.g. id 128 "Wraith Change": EnableOn "b317 & !b1300", OnStart "b1300").
// Slot boundaries also match the Bible's field order: 10 numeric fields
// (FirstDay/Month/Year, LastDay/Month/Year, Random, Duration, PreHoldoff,
// PostHoldoff) at 2 bytes each plus a 4-byte Flags field sums to exactly 24,
// matching EnableOn's offset.
public struct TimedEventSource: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let enableOn: String // test expression
    public let onStart: String  // set expression
    public let onEnd: String    // set expression

    enum Layout {
        static let enableOnOffset = 24
        static let onStartOffset = 279
        static let onEndOffset = 534
        static let slotSize = 255
    }

    public static func decodeAll(from library: GameDataLibrary) -> [TimedEventSource] {
        library.resources(ofType: "crön").compactMap(decode)
    }

    private static func decode(_ resource: GameResource) -> TimedEventSource? {
        let reader = ByteReader(resource.data)
        do {
            let enableOn = try reader.macRomanCString(at: Layout.enableOnOffset, maxLength: Layout.slotSize)
            let onStart = try reader.macRomanCString(at: Layout.onStartOffset, maxLength: Layout.slotSize)
            let onEnd = try reader.macRomanCString(at: Layout.onEndOffset, maxLength: Layout.slotSize)
            return TimedEventSource(id: resource.id, name: resource.name, enableOn: enableOn, onStart: onStart, onEnd: onEnd)
        } catch {
            return nil
        }
    }
}

// MARK: - Disaster (öops)

// Nova Bible, "The öops resource" (lines 1795-1821). ActivateOn's offset
// confirmed against all 19 real öops resources (valid slot for every one;
// 1 has real non-empty content: id 145 "A shortage in supply" -> "!b80").
// Slot boundary matches the Bible's field order exactly: 5 leading 2-byte
// numeric fields (Stellar, Commodity, PriceDelta, Duration, Freq) sum to 10.
public struct DisasterSource: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let activateOn: String // test expression

    enum Layout {
        static let activateOnOffset = 10
        static let slotSize = 255
    }

    public static func decodeAll(from library: GameDataLibrary) -> [DisasterSource] {
        library.resources(ofType: "öops").compactMap(decode)
    }

    private static func decode(_ resource: GameResource) -> DisasterSource? {
        let reader = ByteReader(resource.data)
        do {
            let activateOn = try reader.macRomanCString(at: Layout.activateOnOffset, maxLength: Layout.slotSize)
            return DisasterSource(id: resource.id, name: resource.name, activateOn: activateOn)
        } catch {
            return nil
        }
    }
}

// MARK: - Character (përs)

// Nova Bible, "The përs resource" (lines 2111-2346). ActiveOn's offset
// confirmed against all 516 real përs resources (valid slot for every one;
// 17 have real non-empty content spanning many distinct named characters,
// e.g. "Jack Folstam" -> "b0 & !b8", "Techerakh" -> "!b222", "Eamon
// Flannigan" -> "!b175"). This is the field the Bible spells "ActiveOn"
// (not "ActivateOn" as in öops/oütf) - confirmed from the Bible text itself,
// not a typo introduced here.
public struct CharacterSource: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let activeOn: String // test expression

    enum Layout {
        static let activeOnOffset = 52
        static let slotSize = 255
    }

    public static func decodeAll(from library: GameDataLibrary) -> [CharacterSource] {
        library.resources(ofType: "përs").compactMap(decode)
    }

    private static func decode(_ resource: GameResource) -> CharacterSource? {
        let reader = ByteReader(resource.data)
        do {
            let activeOn = try reader.macRomanCString(at: Layout.activeOnOffset, maxLength: Layout.slotSize)
            return CharacterSource(id: resource.id, name: resource.name, activeOn: activeOn)
        } catch {
            return nil
        }
    }
}

// MARK: - Planet/Stellar (spöb)

// Nova Bible, "The spöb resource" (lines 2767-3004). All four set-expression
// offsets confirmed against all 411 real spöb resources - every resource
// decodes a valid slot at all four offsets. OnDominate and OnDestroy have
// real non-empty content (272 of 411 each; every one found in this
// scenario's data reads exactly "b6100" for OnDominate and "b6200" for
// OnDestroy - a generic per-planet domination/destruction tracking
// convention this scenario evidently uses everywhere). OnRelease and
// OnRegen are empty for all 411 real resources in this scenario (a
// scenario is free to never use a given field) - their offsets are
// confirmed structurally (a valid, in-bounds, correctly-terminated slot for
// every resource) and by the Bible's documented field order: OnRelease
// immediately follows OnDominate with no intervening field (54 + 255 =
// 309), and OnRegen immediately follows OnDestroy with no intervening field
// (582 + 255 = 837). OnDominate's own offset (54) and OnDestroy's offset
// (582) additionally line up with the Bible's field order: a run of numeric
// header fields before OnDominate, and seven more numeric fields (Fee,
// Gravity, Weapon, Strength, DeadType, DeadTime, ExplodType) between
// OnRelease and OnDestroy.
//
// The Bible documents no control-bit *test* expression field for spöb.
public struct PlanetSource: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let onDominate: String // set expression
    public let onRelease: String  // set expression
    public let onDestroy: String  // set expression
    public let onRegen: String    // set expression

    enum Layout {
        static let onDominateOffset = 54
        static let onReleaseOffset = 309
        static let onDestroyOffset = 582
        static let onRegenOffset = 837
        static let slotSize = 255
    }

    public static func decodeAll(from library: GameDataLibrary) -> [PlanetSource] {
        library.resources(ofType: "spöb").compactMap(decode)
    }

    private static func decode(_ resource: GameResource) -> PlanetSource? {
        let reader = ByteReader(resource.data)
        do {
            let onDominate = try reader.macRomanCString(at: Layout.onDominateOffset, maxLength: Layout.slotSize)
            let onRelease = try reader.macRomanCString(at: Layout.onReleaseOffset, maxLength: Layout.slotSize)
            let onDestroy = try reader.macRomanCString(at: Layout.onDestroyOffset, maxLength: Layout.slotSize)
            let onRegen = try reader.macRomanCString(at: Layout.onRegenOffset, maxLength: Layout.slotSize)
            return PlanetSource(id: resource.id, name: resource.name, onDominate: onDominate, onRelease: onRelease, onDestroy: onDestroy, onRegen: onRegen)
        } catch {
            return nil
        }
    }
}

// MARK: - System (sÿst)

// Nova Bible, "The sÿst resource" (lines 3005-3134). Visibility's offset
// confirmed against all 545 real sÿst resources (valid slot for every one;
// 271 have real non-empty content across many named systems, e.g. "Sol" ->
// "!(b147 | b305)", "Procyon" -> "!b36", "Glimmer" -> "!(b6300 | b6302)").
// The Bible documents no control-bit *set* expression field for sÿst.
public struct SystemSource: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let visibility: String // test expression

    enum Layout {
        static let visibilityOffset = 150
        static let slotSize = 255
    }

    public static func decodeAll(from library: GameDataLibrary) -> [SystemSource] {
        library.resources(ofType: "sÿst").compactMap(decode)
    }

    private static func decode(_ resource: GameResource) -> SystemSource? {
        let reader = ByteReader(resource.data)
        do {
            let visibility = try reader.macRomanCString(at: Layout.visibilityOffset, maxLength: Layout.slotSize)
            return SystemSource(id: resource.id, name: resource.name, visibility: visibility)
        } catch {
            return nil
        }
    }
}

// MARK: - Fleet (flët)

// Nova Bible, "The flët resource" (lines 889-932). AppearOn's offset
// confirmed against all 128 real flët resources (valid slot for every one;
// 2 have real non-empty content, both reading "!(b332 | b148)"). Slot
// boundary matches the Bible's field order exactly: 15 leading 2-byte
// numeric fields (LeadShipType, EscortType x4, Min x4, Max x4, Govt,
// LinkSyst) sum to exactly 30.
public struct FleetSource: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let appearOn: String // test expression

    enum Layout {
        static let appearOnOffset = 30
        static let slotSize = 255
    }

    public static func decodeAll(from library: GameDataLibrary) -> [FleetSource] {
        library.resources(ofType: "flët").compactMap(decode)
    }

    private static func decode(_ resource: GameResource) -> FleetSource? {
        let reader = ByteReader(resource.data)
        do {
            let appearOn = try reader.macRomanCString(at: Layout.appearOnOffset, maxLength: Layout.slotSize)
            return FleetSource(id: resource.id, name: resource.name, appearOn: appearOn)
        } catch {
            return nil
        }
    }
}

// MARK: - Junk Type (jünk)

// Nova Bible, "The jünk resource" (lines 1166-1207). BuyOn/SellOn offsets
// confirmed against all 23 real jünk resources (valid slot for every one at
// both offsets; BuyOn has 1 real non-empty sample, "b43"; no real jünk
// resource in this scenario's data uses SellOn). The two-slot arithmetic is
// an exact fit for the resource's total size with no remainder: 166 + 255
// (BuyOn) + 255 (SellOn) = 676, exactly the size of every real jünk
// resource - strong structural confirmation even though SellOn itself has
// no non-empty sample to check content against.
public struct JunkTypeSource: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let buyOn: String  // test expression
    public let sellOn: String // test expression

    enum Layout {
        static let buyOnOffset = 166
        static let sellOnOffset = 421
        static let slotSize = 255
    }

    public static func decodeAll(from library: GameDataLibrary) -> [JunkTypeSource] {
        library.resources(ofType: "jünk").compactMap(decode)
    }

    private static func decode(_ resource: GameResource) -> JunkTypeSource? {
        let reader = ByteReader(resource.data)
        do {
            let buyOn = try reader.macRomanCString(at: Layout.buyOnOffset, maxLength: Layout.slotSize)
            let sellOn = try reader.macRomanCString(at: Layout.sellOnOffset, maxLength: Layout.slotSize)
            return JunkTypeSource(id: resource.id, name: resource.name, buyOn: buyOn, sellOn: sellOn)
        } catch {
            return nil
        }
    }
}
