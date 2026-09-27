import Foundation

// Decodes a `shïp` resource's raw data (see GameResource.data) into its
// documented fields.
//
// Layout derivation: unlike the pilot .plt format, there is no byte-exact
// community doc for shïp resources. Instead, the official developer
// specification - `Nova Bible.txt` (by the original game's programmer),
// section "The shïp resource" - documents every field's meaning, in its
// on-disk order, as plain prose. This is a classic Mac "ResEdit template"
// style resource: fields are packed byte-adjacent in exactly the order
// documented, with NO compiler struct padding (a property of the classic
// resource template system, not a C struct), so field order in the doc maps
// directly to byte order with zero gaps.
//
// Two things the Nova Bible does NOT state, and had to be determined
// empirically (see ShipDefinitionTests, which decodes real ships and checks
// plausibility/consistency):
//
//   1. Byte order. Unlike the .rez container's own BRGR framing (little-
//      endian outside the big-endian resource map - see RezArchive.swift),
//      the DATA *inside* a resource is a straight, unconverted port of the
//      original 68k/PowerPC classic Mac resource bytes, which were always
//      big-endian. Decoding as little-endian produced nonsense (huge/
//      negative/inconsistent stats); decoding as big-endian immediately
//      produced clean, plausible values for every ship tried.
//
//   2. Element width of the "(x8)" array fields. WeapType/WeapCount/
//      AmmoLoad/DefaultItems/ItemCount are documented as "(x8)" without a
//      stated element size. WeapType's own doc text says its *vanilla*
//      valid range is 128-191 - exactly the range that fits in a single
//      unsigned byte alongside the 0/255 "no weapon" sentinels (real
//      installs with plugins/expansions go higher, up to 234 observed,
//      still comfortably inside one byte). Treating
//      these arrays as 8x2-byte (16 bytes each) put Cost at an offset that
//      decoded to nonsense (e.g. a negative "cost"); treating them as
//      8x1-byte (8 bytes each) put Cost exactly where a plausible, cleanly
//      tiered value appeared for every sample ship (Shuttle 10,000 up to
//      Kestrel 50,000,000), and made WeapType/WeapCount/AmmoLoad
//      internally self-consistent (e.g. a ship's WeapCount is only nonzero
//      at the same array index as its nonzero WeapType, and AmmoLoad is
//      only nonzero for weapon slots that plausibly use ammunition).
//
// Confidence: fields are labeled per-field below as verified (cross-checked
// against multiple real ships and, where possible, known EV Nova facts -
// e.g. Kestrel is a plot-reward ship never sold in shipyards, and decodes to
// an implausibly high TechLevel of 8000, which is exactly the kind of
// "never meets any shipyard's tech level" value a scenario author would use
// to make a ship permanently unpurchasable) or probable (plausible small
// values, internally consistent, but not independently cross-checked
// against a known-correct reference value).
//
// SECOND PASS - everything after Flags2 (Availability onward). The doc
// comment above (and the original plan for this file) assumed the fields
// after Flags2 would need sequential, position-dependent Pascal-string
// walking, because that's how classic Mac resource text fields are usually
// documented. Empirical testing against all 288 real shïp resources in this
// install (see ShipDefinitionTests) disproved that assumption for this
// specific resource type:
//
//   - Every single shïp resource in the real game data is exactly 1860
//     bytes, with zero exceptions. That alone is strong evidence this is a
//     fixed-layout ResEdit-style template, not a truly variable-length
//     structure.
//   - Every string field (Availability, AppearOn, OnPurchase, OnCapture,
//     OnRetire, ShortName, CommName, Long Name, Subtitle, MovieFile) was
//     empirically found to start at the exact same absolute byte offset in
//     every ship that has non-blank content there - including cases like
//     "Shuttle;Second-Hand - poor" whose ShortName ("Shuttle\n- used -", 17
//     chars) is much longer than plain "Shuttle" (7 chars) yet the NEXT
//     field (CommName) still starts at the same fixed offset in both. This
//     proves each string field is a fixed-size reserved buffer (NUL-
//     terminated text, unused tail bytes left as whatever was last written
//     there - not walked/variable), decodable with
//     ByteReader.macRomanCString(at:maxLength:) at a static offset, exactly
//     like the numeric header fields above.
//   - IMPORTANT: the on-disk field ORDER in this tail section does NOT
//     always match the Nova Bible's prose order. The Bible lists Subtitle,
//     Flags3, UpgradeTo, EscUpgrdCost, EscSellValue, and EscortType between
//     OnRetire and ShortName, but empirically ShortName starts immediately
//     (offset 1486) right where OnRetire's reserved block ends (1231 + 255
//     = 1486), with zero bytes of room for those numeric fields or
//     Subtitle in between. Those fields are actually stored AFTER Long
//     Name, in the range 1766-1859 (see Layout below). Every field's exact
//     on-disk position below was determined empirically, not by trusting
//     Bible prose order - see ShipDefinitionTests for the validation.
//
// Confidence per field is noted at each property below. "Verified" means
// cross-checked against real, semantically-meaningful non-zero/non-blank
// data (e.g. UpgradeTo values resolving to real ship IDs, Flags3 bits
// exactly matching the Bible's documented bit list with zero stray bits,
// BuyRandom/HireRandom always falling in 0-100). "Probable" means the field
// is positioned correctly by byte-budget elimination between two verified
// anchors, but every one of the 288 real ships in this install happens to
// leave it at zero/blank, so the exact byte width could not be
// independently cross-checked against real non-zero data.
public struct ShipDefinition: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String

    // MARK: - Performance stats (Nova Bible: "first nine fields") - verified

    public var holds: Int16
    public var shield: Int16
    public var accel: Int16
    public var speed: Int16
    public var maneuver: Int16
    public var fuel: Int16
    public var freeMass: Int16
    public var armor: Int16
    public var shieldRecharge: Int16

    // MARK: - Stock weapon loadout (4 Int16 slots each) - verified

    // Verified against a real pilot flying a Mod Starbridge (see
    // Layout.slotCount). WeapType is a wëap ID (128+), -1 or 0 = empty slot.
    // Bible slots 5-8 are not located; every stock ship leaves the likely
    // spot (908-975) zeroed.
    public var weapType: [Int16]
    public var weapCount: [Int16]
    public var ammoLoad: [Int16]

    // MARK: - Weapon slot limits - probable

    public var maxGun: Int16
    public var maxTur: Int16

    // MARK: - Purchase info - verified

    public var techLevel: Int16
    public var cost: Int32

    // MARK: - Explosion / death info - probable

    public var deathDelay: Int16
    public var armorRecharge: Int16
    public var explode1: Int16
    public var explode2: Int16

    // MARK: - Display / physical stats - verified

    public var dispWeight: Int16
    public var mass: Int16
    public var length: Int16

    // MARK: - AI / crew / government - verified (crew, inherentGovt), probable (rest)

    public var inherentAI: Int16
    public var crew: Int16
    public var strength: Int16
    // Verified via range: real values seen fall cleanly into the Nova
    // Bible's documented bands (-1 no inherent govt; 128-383 combat+
    // attributes; 1128-1383 attributes-only, i.e. real govt id + 1000).
    public var inherentGovt: Int16

    // MARK: - Misc flags - probable

    // Bitmask fields - exposed as UInt16 rather than Int16 since they are
    // never meant to be read as signed numbers (the highest documented bit
    // is 0x8000, which would otherwise print as a negative Int16). Every
    // sample ship's decoded bits fall entirely within the Nova Bible's
    // documented bit list for Flags/Flags2, with no stray high bits.
    public var flags: UInt16
    public var podCount: Int16

    // MARK: - Default equipment (4 Int16 slots each) - verified

    // oütf IDs (128+), -1 or 0 = empty slot.

    public var defaultItems: [Int16]
    public var itemCount: [Int16]

    // MARK: - Misc (end of statically-decodable header block) - probable

    public var fuelRegen: Int16
    public var skillVar: Int16
    public var flags2: UInt16

    // MARK: - Purchase/appearance gating expressions - verified

    // Control bit test/set expressions, e.g. "!b424 & P30" or "b8888".
    // Decoded via a fixed absolute offset + NUL-terminated read (see file
    // doc comment above) - empty string means "blank/unused" per the Nova
    // Bible. Cross-checked across the real ship set: every non-blank value
    // decoded to well-formed expression syntax (balanced parens, only
    // "&|!bP0-9 " characters), never garbage.
    public var availability: String
    public var appearOn: String
    public var onPurchase: String

    // MARK: - Ionization - verified

    // Both fields are nonzero for all 288 real ships, with small,
    // plausible magnitudes (Deionize 1-500ish, IonizeMax 3-3000ish).
    public var deionize: Int16
    public var ionizeMax: Int16

    // MARK: - Key carried ship - probable

    // Always 0 across all 288 real ships in this install, so this couldn't
    // be cross-checked against a real non-zero reference value. Positioned
    // by Bible order between IonizeMax and DefaultItms2.
    public var keyCarried: Int16

    // MARK: - Second default equipment array (4 Int16 slots each) - verified

    // Default items 5-8, same encoding as defaultItems/itemCount above.
    // Populated on the "Second-Hand - upgraded" escort variants (outfits
    // such as 180, 186, 193, 197, 228); -1 everywhere else. The stray
    // "item=1, count=0" values seen when this was read one byte at a time
    // were the high bytes of outfit IDs of 256 and up.
    public var defaultItems2: [Int16]
    public var itemCount2: [Int16]

    // MARK: - Contribute / Require 64-bit flags - probable

    // The Nova Bible describes "these two Contribute fields" (and likewise
    // Require) as together forming a single 64-bit flag. Empirically only
    // 32 bits total fit the byte budget between ItemCount2 and the
    // verified BuyRandom offset, so each field here is modeled as 16 bits
    // rather than the Bible's implied 32 bits per field - a known,
    // documented discrepancy. contribute2 is cross-checked against 24 real
    // ships with small, plausible bitmask-like values (2-207); the other
    // three are always 0 across the real ship set and are positioned by
    // elimination only.
    public var contribute1: Int16
    public var contribute2: Int16
    public var require1: Int16
    public var require2: Int16

    // MARK: - Purchase/hire randomness - verified

    // Both fields fall strictly within 0-100 for all 288 real ships,
    // exactly matching the Nova Bible's documented "percent chance, 0-100"
    // semantics with zero outliers.
    public var buyRandom: Int16
    public var hireRandom: Int16

    // MARK: - Capture/retire expressions - verified

    // Same encoding as availability/appearOn/onPurchase above. onCapture
    // and onRetire decode to well-formed expression text wherever non-
    // blank (e.g. onCapture "b8888" on 171 ships that share it with
    // onPurchase; onRetire "!b4322" on the single ship that uses it).
    public var onCapture: String
    public var onRetire: String

    // MARK: - Tail: subtitle, flags3, escort upgrade info, names - verified/probable

    // Subtitle is verified (clean text on 257/288 ships, e.g. "Flagship
    // Class", "Prospector"). Flags3 is verified: every real ship's decoded
    // bits fall entirely within the Bible's documented Flags3 bit list
    // (0x0001/0x0002/0x0040/0x0100/0x0200 observed, no stray bits) - e.g.
    // "Asteroid Miner" decodes to exactly the "destroys asteroids" +
    // "scoops debris" bits its name implies. UpgradeTo is verified: every
    // one of the 154 real ships with a nonzero UpgradeTo resolves to a
    // real ship ID in the same game (e.g. Valkyrie id 137 -> id 280).
    // EscUpgrdCost is verified: nonzero exactly when UpgradeTo is set, with
    // plausible cost magnitudes (Shuttle 5,000 up to Fed Carrier
    // 3,000,000). EscSellValue is probable (always 0 across the real ship
    // set - matches the Bible's "defaults to 10% of cost if <= 0", so
    // commonly left unset - positioned by elimination). EscortType is
    // verified: all 288 ships decode to exactly one of the Bible's 4
    // documented categories (0-3), with a plausible distribution across
    // them. ShortName/CommName/LongName are verified (always present,
    // readable shipyard/hail/purchase text on every ship). MovieFile is
    // probable (always blank across the real ship set, so the exact
    // reserved width - assumed to run to the resource's end - could not be
    // cross-checked against a real non-blank filename).
    public var subtitle: String
    public var flags3: UInt16
    public var upgradeTo: Int16
    public var escUpgrdCost: Int32
    public var escSellValue: Int32
    public var escortType: Int16
    public var shortName: String
    public var commName: String
    public var longName: String
    public var movieFile: String

    public init(
        id: Int,
        name: String,
        holds: Int16,
        shield: Int16,
        accel: Int16,
        speed: Int16,
        maneuver: Int16,
        fuel: Int16,
        freeMass: Int16,
        armor: Int16,
        shieldRecharge: Int16,
        weapType: [Int16],
        weapCount: [Int16],
        ammoLoad: [Int16],
        maxGun: Int16,
        maxTur: Int16,
        techLevel: Int16,
        cost: Int32,
        deathDelay: Int16,
        armorRecharge: Int16,
        explode1: Int16,
        explode2: Int16,
        dispWeight: Int16,
        mass: Int16,
        length: Int16,
        inherentAI: Int16,
        crew: Int16,
        strength: Int16,
        inherentGovt: Int16,
        flags: UInt16,
        podCount: Int16,
        defaultItems: [Int16],
        itemCount: [Int16],
        fuelRegen: Int16,
        skillVar: Int16,
        flags2: UInt16,
        availability: String,
        appearOn: String,
        onPurchase: String,
        deionize: Int16,
        ionizeMax: Int16,
        keyCarried: Int16,
        defaultItems2: [Int16],
        itemCount2: [Int16],
        contribute1: Int16,
        contribute2: Int16,
        require1: Int16,
        require2: Int16,
        buyRandom: Int16,
        hireRandom: Int16,
        onCapture: String,
        onRetire: String,
        subtitle: String,
        flags3: UInt16,
        upgradeTo: Int16,
        escUpgrdCost: Int32,
        escSellValue: Int32,
        escortType: Int16,
        shortName: String,
        commName: String,
        longName: String,
        movieFile: String
    ) {
        self.id = id
        self.name = name
        self.holds = holds
        self.shield = shield
        self.accel = accel
        self.speed = speed
        self.maneuver = maneuver
        self.fuel = fuel
        self.freeMass = freeMass
        self.armor = armor
        self.shieldRecharge = shieldRecharge
        self.weapType = weapType
        self.weapCount = weapCount
        self.ammoLoad = ammoLoad
        self.maxGun = maxGun
        self.maxTur = maxTur
        self.techLevel = techLevel
        self.cost = cost
        self.deathDelay = deathDelay
        self.armorRecharge = armorRecharge
        self.explode1 = explode1
        self.explode2 = explode2
        self.dispWeight = dispWeight
        self.mass = mass
        self.length = length
        self.inherentAI = inherentAI
        self.crew = crew
        self.strength = strength
        self.inherentGovt = inherentGovt
        self.flags = flags
        self.podCount = podCount
        self.defaultItems = defaultItems
        self.itemCount = itemCount
        self.fuelRegen = fuelRegen
        self.skillVar = skillVar
        self.flags2 = flags2
        self.availability = availability
        self.appearOn = appearOn
        self.onPurchase = onPurchase
        self.deionize = deionize
        self.ionizeMax = ionizeMax
        self.keyCarried = keyCarried
        self.defaultItems2 = defaultItems2
        self.itemCount2 = itemCount2
        self.contribute1 = contribute1
        self.contribute2 = contribute2
        self.require1 = require1
        self.require2 = require2
        self.buyRandom = buyRandom
        self.hireRandom = hireRandom
        self.onCapture = onCapture
        self.onRetire = onRetire
        self.subtitle = subtitle
        self.flags3 = flags3
        self.upgradeTo = upgradeTo
        self.escUpgrdCost = escUpgrdCost
        self.escSellValue = escSellValue
        self.escortType = escortType
        self.shortName = shortName
        self.commName = commName
        self.longName = longName
        self.movieFile = movieFile
    }

    // MARK: - Layout

    // Cumulative byte offsets, big-endian, assuming zero struct padding
    // (see file doc comment above), in the exact order the Nova Bible
    // documents them. Every offset here precedes the first variable-length
    // Pascal string field (Availability), so all of them are static across
    // every ship resource regardless of that resource's later string
    // content.
    enum Layout {
        static let holds = 0
        static let shield = 2
        static let accel = 4
        static let speed = 6
        static let maneuver = 8
        static let fuel = 10
        static let freeMass = 12
        static let armor = 14
        static let shieldRecharge = 16

        // The Bible lists these arrays as "(x8)", but each block here holds
        // four big-endian Int16 values: the Mod Starbridge reads as stock
        // weapons 129/128/135 x 3/2/2 and default outfits 238/239, which
        // matches a real pilot flying one. Reading them as eight single
        // bytes gave 0,129,0,128,... and couldn't hold outfit IDs above 255.
        static let slotCount = 4

        static let weapType = 18       // [Int16 x 4], 8 bytes
        static let weapCount = 26      // [Int16 x 4], 8 bytes
        static let ammoLoad = 34       // [Int16 x 4], 8 bytes

        static let maxGun = 42
        static let maxTur = 44

        static let techLevel = 46
        static let cost = 48           // Int32, 4 bytes

        static let deathDelay = 52
        static let armorRecharge = 54
        static let explode1 = 56
        static let explode2 = 58
        static let dispWeight = 60
        static let mass = 62
        static let length = 64

        static let inherentAI = 66
        static let crew = 68
        static let strength = 70
        static let inherentGovt = 72

        static let flags = 74
        static let podCount = 76

        static let defaultItems = 78   // [Int16 x 4], 8 bytes
        static let itemCount = 86      // [Int16 x 4], 8 bytes

        static let fuelRegen = 94
        static let skillVar = 96
        static let flags2 = 98

        // Total size of the statically-decodable header block that every
        // real shïp resource satisfies.
        static let minimumDecodableSize = 100

        // MARK: - Tail layout (offset 100 onward)
        //
        // Unlike the header above, these are NOT cumulative-from-zero
        // struct offsets - they're absolute byte offsets empirically
        // validated against all 288 real shïp resources (see
        // ShipDefinitionTests and the file doc comment). Every real
        // resource in this install is exactly 1860 bytes; these offsets
        // assume that same fixed layout and gracefully decode to
        // empty/zero defaults if a resource is shorter (see decode(from:)).

        // Expression string fields - fixed 255-byte reserved buffers,
        // NUL-terminated text, MacRoman-encoded. 255 is the empirically
        // confirmed spacing between consecutive fields of this kind
        // (108 -> 363 -> 618, each exactly 255 apart).
        static let availability = 108
        static let appearOn = 363
        static let onPurchase = 618
        static let onCapture = 976
        static let onRetire = 1231
        static let expressionStringMaxLength = 255

        static let deionize = 874
        static let ionizeMax = 876
        static let keyCarried = 878

        static let defaultItems2 = 880  // [Int16 x 4], 8 bytes
        static let itemCount2 = 888     // [Int16 x 4], 8 bytes

        static let contribute1 = 896
        static let contribute2 = 898
        static let require1 = 900
        static let require2 = 902

        static let buyRandom = 904
        static let hireRandom = 906

        // Name/text fields - fixed reserved buffers of varying size (each
        // sized to comfortably fit the longest real value seen plus a NUL
        // terminator), NUL-terminated, MacRoman-encoded.
        static let shortName = 1486
        static let shortNameMaxLength = 64
        static let commName = 1550
        static let commNameMaxLength = 32
        static let longName = 1582
        static let longNameMaxLength = 184
        static let subtitle = 1766
        static let subtitleMaxLength = 64

        static let flags3 = 1830
        static let upgradeTo = 1832
        static let escUpgrdCost = 1834
        static let escSellValue = 1838
        static let escortType = 1842

        // Runs to the resource's end (1844 + 16 = 1860, the fixed total
        // resource size observed for every real ship).
        static let movieFile = 1844
        static let movieFileMaxLength = 16
    }

    // MARK: - Decoding

    public static func decodeAll(from library: GameDataLibrary) -> [ShipDefinition] {
        library.resources(ofType: "shïp").compactMap { decode(from: $0) }
    }

    // Returns nil (rather than a blank/zeroed value) for any resource too
    // short to contain the full static header block - a malformed or
    // unexpectedly-truncated resource should be skipped rather than shown
    // with meaningless zeros.
    public static func decode(from resource: GameResource) -> ShipDefinition? {
        let reader = ByteReader(resource.data)

        do {
            let holds = try reader.int16(at: Layout.holds, byteOrder: .big)
            let shield = try reader.int16(at: Layout.shield, byteOrder: .big)
            let accel = try reader.int16(at: Layout.accel, byteOrder: .big)
            let speed = try reader.int16(at: Layout.speed, byteOrder: .big)
            let maneuver = try reader.int16(at: Layout.maneuver, byteOrder: .big)
            let fuel = try reader.int16(at: Layout.fuel, byteOrder: .big)
            let freeMass = try reader.int16(at: Layout.freeMass, byteOrder: .big)
            let armor = try reader.int16(at: Layout.armor, byteOrder: .big)
            let shieldRecharge = try reader.int16(at: Layout.shieldRecharge, byteOrder: .big)

            let weapType = try readInt16Array(reader, at: Layout.weapType, count: Layout.slotCount)
            let weapCount = try readInt16Array(reader, at: Layout.weapCount, count: Layout.slotCount)
            let ammoLoad = try readInt16Array(reader, at: Layout.ammoLoad, count: Layout.slotCount)

            let maxGun = try reader.int16(at: Layout.maxGun, byteOrder: .big)
            let maxTur = try reader.int16(at: Layout.maxTur, byteOrder: .big)

            let techLevel = try reader.int16(at: Layout.techLevel, byteOrder: .big)
            let cost = try reader.int32(at: Layout.cost, byteOrder: .big)

            let deathDelay = try reader.int16(at: Layout.deathDelay, byteOrder: .big)
            let armorRecharge = try reader.int16(at: Layout.armorRecharge, byteOrder: .big)
            let explode1 = try reader.int16(at: Layout.explode1, byteOrder: .big)
            let explode2 = try reader.int16(at: Layout.explode2, byteOrder: .big)
            let dispWeight = try reader.int16(at: Layout.dispWeight, byteOrder: .big)
            let mass = try reader.int16(at: Layout.mass, byteOrder: .big)
            let length = try reader.int16(at: Layout.length, byteOrder: .big)

            let inherentAI = try reader.int16(at: Layout.inherentAI, byteOrder: .big)
            let crew = try reader.int16(at: Layout.crew, byteOrder: .big)
            let strength = try reader.int16(at: Layout.strength, byteOrder: .big)
            let inherentGovt = try reader.int16(at: Layout.inherentGovt, byteOrder: .big)

            let flags = UInt16(bitPattern: try reader.int16(at: Layout.flags, byteOrder: .big))
            let podCount = try reader.int16(at: Layout.podCount, byteOrder: .big)

            let defaultItems = try readInt16Array(reader, at: Layout.defaultItems, count: Layout.slotCount)
            let itemCount = try readInt16Array(reader, at: Layout.itemCount, count: Layout.slotCount)

            let fuelRegen = try reader.int16(at: Layout.fuelRegen, byteOrder: .big)
            let skillVar = try reader.int16(at: Layout.skillVar, byteOrder: .big)
            let flags2 = UInt16(bitPattern: try reader.int16(at: Layout.flags2, byteOrder: .big))

            // Tail fields (offset 100 onward - see file doc comment and
            // Layout above). These are read leniently (try?, with
            // empty/zero fallback) rather than as part of the throwing
            // chain above: every real ship resource is exactly 1860 bytes
            // and decodes all of them, but a shorter/malformed resource
            // (e.g. from an unusual plugin) should still yield a usable
            // ShipDefinition with just the header populated, rather than
            // losing the whole ship.
            let availability = readExpressionString(reader, at: Layout.availability)
            let appearOn = readExpressionString(reader, at: Layout.appearOn)
            let onPurchase = readExpressionString(reader, at: Layout.onPurchase)

            let deionize = (try? reader.int16(at: Layout.deionize, byteOrder: .big)) ?? 0
            let ionizeMax = (try? reader.int16(at: Layout.ionizeMax, byteOrder: .big)) ?? 0
            let keyCarried = (try? reader.int16(at: Layout.keyCarried, byteOrder: .big)) ?? 0

            let defaultItems2 = (try? readInt16Array(reader, at: Layout.defaultItems2, count: Layout.slotCount)) ?? Array(repeating: -1, count: Layout.slotCount)
            let itemCount2 = (try? readInt16Array(reader, at: Layout.itemCount2, count: Layout.slotCount)) ?? Array(repeating: 0, count: Layout.slotCount)

            let contribute1 = (try? reader.int16(at: Layout.contribute1, byteOrder: .big)) ?? 0
            let contribute2 = (try? reader.int16(at: Layout.contribute2, byteOrder: .big)) ?? 0
            let require1 = (try? reader.int16(at: Layout.require1, byteOrder: .big)) ?? 0
            let require2 = (try? reader.int16(at: Layout.require2, byteOrder: .big)) ?? 0

            let buyRandom = (try? reader.int16(at: Layout.buyRandom, byteOrder: .big)) ?? 0
            let hireRandom = (try? reader.int16(at: Layout.hireRandom, byteOrder: .big)) ?? 0

            let onCapture = readExpressionString(reader, at: Layout.onCapture)
            let onRetire = readExpressionString(reader, at: Layout.onRetire)

            let subtitle = (try? reader.macRomanCString(at: Layout.subtitle, maxLength: Layout.subtitleMaxLength)) ?? ""
            let flags3 = UInt16(bitPattern: (try? reader.int16(at: Layout.flags3, byteOrder: .big)) ?? 0)
            let upgradeTo = (try? reader.int16(at: Layout.upgradeTo, byteOrder: .big)) ?? 0
            let escUpgrdCost = (try? reader.int32(at: Layout.escUpgrdCost, byteOrder: .big)) ?? 0
            let escSellValue = (try? reader.int32(at: Layout.escSellValue, byteOrder: .big)) ?? 0
            let escortType = (try? reader.int16(at: Layout.escortType, byteOrder: .big)) ?? -1

            let shortName = (try? reader.macRomanCString(at: Layout.shortName, maxLength: Layout.shortNameMaxLength)) ?? ""
            let commName = (try? reader.macRomanCString(at: Layout.commName, maxLength: Layout.commNameMaxLength)) ?? ""
            let longName = (try? reader.macRomanCString(at: Layout.longName, maxLength: Layout.longNameMaxLength)) ?? ""
            let movieFile = (try? reader.macRomanCString(at: Layout.movieFile, maxLength: Layout.movieFileMaxLength)) ?? ""

            return ShipDefinition(
                id: resource.id,
                name: resource.name,
                holds: holds,
                shield: shield,
                accel: accel,
                speed: speed,
                maneuver: maneuver,
                fuel: fuel,
                freeMass: freeMass,
                armor: armor,
                shieldRecharge: shieldRecharge,
                weapType: weapType,
                weapCount: weapCount,
                ammoLoad: ammoLoad,
                maxGun: maxGun,
                maxTur: maxTur,
                techLevel: techLevel,
                cost: cost,
                deathDelay: deathDelay,
                armorRecharge: armorRecharge,
                explode1: explode1,
                explode2: explode2,
                dispWeight: dispWeight,
                mass: mass,
                length: length,
                inherentAI: inherentAI,
                crew: crew,
                strength: strength,
                inherentGovt: inherentGovt,
                flags: flags,
                podCount: podCount,
                defaultItems: defaultItems,
                itemCount: itemCount,
                fuelRegen: fuelRegen,
                skillVar: skillVar,
                flags2: flags2,
                availability: availability,
                appearOn: appearOn,
                onPurchase: onPurchase,
                deionize: deionize,
                ionizeMax: ionizeMax,
                keyCarried: keyCarried,
                defaultItems2: defaultItems2,
                itemCount2: itemCount2,
                contribute1: contribute1,
                contribute2: contribute2,
                require1: require1,
                require2: require2,
                buyRandom: buyRandom,
                hireRandom: hireRandom,
                onCapture: onCapture,
                onRetire: onRetire,
                subtitle: subtitle,
                flags3: flags3,
                upgradeTo: upgradeTo,
                escUpgrdCost: escUpgrdCost,
                escSellValue: escSellValue,
                escortType: escortType,
                shortName: shortName,
                commName: commName,
                longName: longName,
                movieFile: movieFile
            )
        } catch {
            return nil
        }
    }

    // Reads one of the fixed-width expression-string fields (Availability,
    // AppearOn, OnPurchase, OnCapture, OnRetire) at a static offset,
    // falling back to "" (blank/unused, per the Nova Bible's own
    // convention for these fields) if the resource is too short to contain
    // it.
    private static func readExpressionString(_ reader: ByteReader, at offset: Int) -> String {
        (try? reader.macRomanCString(at: offset, maxLength: Layout.expressionStringMaxLength)) ?? ""
    }

    // Reads `count` consecutive big-endian Int16 slots. Unused slots hold
    // -1 or 0, per the Bible.
    private static func readInt16Array(_ reader: ByteReader, at offset: Int, count: Int) throws -> [Int16] {
        try (0..<count).map { index -> Int16 in
            try reader.int16(at: offset + index * 2, byteOrder: .big)
        }
    }
}
