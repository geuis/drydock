import Foundation

// Decodes a `mïsn` (mission definition) resource's raw data (see
// GameResource.data) into its documented fields. This is the STATIC mission
// template/definition that lives in the game's data files (what a mission
// IS - its requirements, rewards, and text) - not to be confused with
// MissionSlot, which tracks a PILOT's live progress through an accepted
// mission. See MissionSlot.swift's doc comment for the full distinction.
//
// Layout derivation: as with ShipDefinition/OutfitDefinition, the Nova
// Bible ("The mïsn resource", lines 1258-1747 of the converted text)
// documents every field's meaning in prose, in roughly the order fields
// appear on disk, with no compiler struct padding. Missions are explicitly
// called out as "the largest and most complex resources in the game", and
// unlike shïp/oütf, prose order here did NOT reliably predict byte order
// for every single field (see per-field confidence notes below) - offsets
// were instead re-derived empirically by decoding all 791 real mission
// resources and checking which offset's aggregate value distribution
// matches each field's documented semantics (exact discrete value sets
// where documented, e.g. PickupMode's four values {-1,0,1,2}; sentinel
// patterns, e.g. ShipSyst's unique six negative sentinels -1...-6; and
// cross-checks against specific named missions, e.g. "25000 Credit Bounty"
// and mission chain names). See MissionDefinitionTests for the
// verification code.
//
// THE KEY DISCOVERY - every mïsn resource in the real game data is exactly
// 1970 bytes, regardless of content, even though the Nova Bible describes
// several trailing fields (AvailBits, OnAccept, OnRefuse, OnSuccess,
// OnFailure, OnAbort, OnShipDone, AcceptButton, RefuseButton) as free-text
// control-bit-expression/button-label strings. These are NOT classic
// variable-length Pascal strings that shift subsequent field offsets - each
// one occupies a fixed-width reserved slot (255 bytes for the seven
// control-bit-expression fields, 32 bytes for the two button-label fields),
// zero-padded, with a 2-byte value at the front of each slot that is
// always the constant 127 (0x007f) and does NOT vary with actual content
// length - it appears to be a leftover fixed "max capacity" marker from the
// authoring tool rather than a real per-resource length prefix. Because
// every field's slot is fixed-width, ALL offsets in a mïsn resource are
// static, including the ones after the first string field - unlike
// shïp/oütf, no sequential Pascal-string walk is needed here.
//
// MISSION CHAINING - the mechanism the task cares most about - works via
// the "Sxxx" operator documented in the NCB (Nova Control Bit) "set
// expression" syntax (Nova Bible lines ~146-227): "Sxxx - start mission ID
// xxx automatically." This token can appear anywhere inside any of the six
// set-expression fields (OnAccept, OnRefuse, OnSuccess, OnFailure, OnAbort,
// OnShipDone), mixed in with other bit-set/clear operators (e.g.
// `"b353 S783"` sets control bit 353 AND starts mission 783). There is no
// separate dedicated "next mission ID" numeric field - chaining is entirely
// embedded in these expression strings. This was confirmed by decoding a
// real story arc (the "Vellos" mission chain, ids 128-146+): e.g. mission
// 129 "Visit Vell-os Homeworld; Vellos2" has OnSuccess = "b351 S797 b512
// b515 b518" (chains to mission 797 on success) and OnRefuse = "S781 b4444"
// (chains to mission 781 if refused); mission 131 "Infiltrate the Rebels;
// Vellos4" has OnSuccess = "b353 S783" and OnAbort = "S818". See
// `startedMissionIDs(in:)` for the parser, and MissionChainResolver for
// walking these links across the whole decoded set.
//
// Confidence labels below follow the ShipDefinition/OutfitDefinition
// convention: "verified" fields matched an exact, small, documented
// discrete value set (e.g. PickupMode's four values) or a unique
// documented sentinel pattern (e.g. ShipSyst's six negative sentinels)
// across all 791 real missions with no stray values, or were confirmed
// against a specific named mission (e.g. AvailStel/TravelStel/ReturnStel's
// government-relative bucket encoding). "Probable" fields have a plausible,
// internally-consistent value distribution but were not independently
// cross-checked against a specific known-correct example. See the honest
// omissions section at the bottom of this file for fields that could not
// be confidently located after real effort.
public struct MissionDefinition: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String

    // MARK: - Availability criteria - verified/probable

    // Where/when the mission is offered. Values use a shared "government-
    // relative" encoding across several fields in this resource (also used
    // by travelStel/returnStel/shipSyst below): -1 and small negatives are
    // special cases (e.g. "any inhabited stellar"), 128-2175 is a specific
    // stellar/system ID, and 9999-31255 selects stellars/systems relative
    // to a specific government (ally/enemy/classmate/other), encoded as
    // bucket-start + government ID.
    public var availStel: Int16
    // Where on a planet the mission is offered (0=mission computer,
    // 1=bar, 2=from ship, 3=spaceport, 4=trading, 5=shipyard, 6=outfitter).
    // Verified: every one of 791 real missions decodes to exactly one of
    // these 7 documented values, no stray values.
    public var availLoc: Int16
    // Required legal record in-system. Probable (doc-order position;
    // plausible small-magnitude values, not independently cross-checked).
    public var availRecord: Int16
    // Minimum combat rating required for this mission to be offered.
    // Verified (re-derived 2026-09-24, corrected from the earlier payVal
    // misassignment at this same offset): -1 means "ignored", 0+ means the
    // player's combat rating must be at least this high. Harder bounty-style
    // missions decode to thresholds like 100/200, easier ones to 5, matching
    // AvailRating's documented semantics far better than PayVal's (see
    // payVal's own doc comment below for where PayVal actually lives). Bible
    // field order for the first six fields is AvailStel, AvailLoc,
    // AvailRecord, AvailRating, AvailRandom - this offset slots in exactly
    // where that order predicts.
    public var availRating: Int16
    // Percentage chance (1-100) the mission is offered at all, recalculated
    // each system entry; 100 = always. Verified: every real mission decodes
    // to a value in 0-100, heavily weighted toward round percentages.
    public var availRandom: Int16

    // MARK: - Travel objectives - verified

    public var travelStel: Int16
    public var returnStel: Int16

    // MARK: - Cargo requirements - verified

    public var cargoType: Int16
    public var cargoQty: Int16
    public var pickupMode: Int16
    public var dropOffMode: Int16
    // Bitmask compared against a government's own ScanMask to determine if
    // this mission's cargo is considered illegal. Verified: real values are
    // clean single-bit-set patterns (e.g. 0x0800, 0x0200, 0x8000).
    public var scanMask: Int16

    // MARK: - Reward - verified

    // What the player receives on success. Verified (re-derived 2026-09-24):
    // PayVal is actually a 4-byte big-endian Int32 at offset 28, not the
    // Int16 field previously guessed at offset 8 (that offset is
    // AvailRating - see its doc comment above). "25000 Credit Bounty"
    // missions decode to exactly 22500 (90% of the named amount) and
    // "50000 Credit Bounty" missions decode to exactly 45000 (also 90%),
    // which is both an exact literal match on the ratio AND the first
    // offset tried that reproduces a named mission's dollar amount at all.
    // Common values across the real data are clean round numbers (15000,
    // 20000, 25000, 40000, 50000, 100000). The negative values are not
    // garbage: they fall exactly within the Bible's documented special-
    // reward sentinel ranges - -10128...-10383 (clean record with a govt),
    // -20128...-20383 (with allies), -30128...-30383 (with classmates), and
    // -40001...-40099 (take this % of the player's cash) - which an Int16
    // read at the wrong offset would not reproduce this cleanly. Preserved
    // as a raw Int32 here rather than decoded into a separate enum, since
    // the exact govt-ID-encoding formula inside each range wasn't
    // independently confirmed; see `payDescription` below for a
    // human-readable interpretation of which documented range a value
    // falls in.
    public var payVal: Int32

    // MARK: - Special ship - verified/probable

    // Number of special mission ships (-1 = none, 0-31 = this many).
    // Verified (re-derived 2026-09-24): this field is actually at offset 32,
    // not 28 - offset 28 (and 30) together form the 4-byte PayVal field
    // (see payVal's doc comment above), so the old ShipCount offset was
    // silently reading PayVal's high 16 bits. The corrected offset still
    // shows exactly the documented -1/0-31 value range with no stray
    // values.
    public var shipCount: Int16
    // Which system the special ships appear in - shares the same
    // government-relative encoding as availStel, plus six unique negative
    // sentinels (-1 initial system ... -6 follow the player). Verified:
    // every one of the six documented sentinels appears, uniquely
    // identifying this field among all candidate offsets tried.
    public var shipSyst: Int16
    // Dude resource ID used to generate the special ships' type/stats
    // (-1 = none, 128-639 = vanilla dude ID range; some plugin data goes
    // higher). Probable: real values mostly fall in the documented range,
    // with plugin content occasionally exceeding it, similar to how
    // ShipDefinition's WeapType range needed real-data-driven widening.
    public var shipDude: Int16
    // The special ships' goal (0=destroy, 1=disable, 2=board, 3=escort,
    // 4=observe, 5=rescue, 6=chase off; -1=none). Verified: exactly the 8
    // documented values appear, no stray values, and cross-checked against
    // "Escort Merchant to <RST>" decoding to 3 (Escort).
    public var shipGoal: Int16
    // Special ship AI behavior override (-1=normal AI, 0=always attack,
    // 1=protect player, 2=attack enemy stellars). Probable: 3 of the 4
    // documented values seen (value 2 - "attack enemy stellars" - never
    // observed in this data, plausible given how rare that behavior is).
    public var shipBehav: Int16
    // STR# resource ID used to name the special ships (-1 = normal names,
    // 128+ = pick a name from this STR#). Probable.
    public var shipNameID: Int16

    // MARK: - Mission briefing text references - probable

    // These are all IDs into the `dësc` resource type (not decoded by this
    // pass), mirroring the pattern already seen in the pilot file's
    // MissionData (briefText/quickBriefText/etc as short IDs). The Nova
    // Bible explicitly notes "ID numbers of 5000 and up are usually the
    // safest" for these fields, which matches the real data closely:
    // briefText clusters in the 5000s, quickBrief in the 6000s,
    // loadCargText in the 7000s, dumpCargoText in the 8000s, and compText
    // in the 9000s - a clean, consistent per-field numbering convention
    // that strongly supports this offset assignment even though no
    // dësc-resource decoder exists yet to cross-check the text itself.
    public var briefText: Int16
    public var quickBrief: Int16
    public var loadCargText: Int16
    public var dumpCargoText: Int16
    public var compText: Int16

    // MARK: - Misc - verified

    // Whether the player can voluntarily abort this mission once accepted.
    // Verified: exactly the 2 documented values (0/1), no stray values at
    // all across all 791 missions - the cleanest signature found in this
    // entire resource.
    public var canAbort: Bool
    // Mission deadline in days (-1 or 0 = no limit, 1+ = this many days).
    // Verified: -1 dominates (92% of missions have no deadline), and the
    // small tail of other values (18, 20, 25, 30, 35, 40, 50, 65, 70) are
    // all plausible day counts, matching the documented semantics well.
    public var timeLimit: Int16
    // Controls display order in bar/BBS mission lists; higher = shown
    // first. Probable: mostly 0 (default), small positive tail (1, 5, 10,
    // 100) consistent with "occasionally bumped up" authoring.
    public var dispWeight: Int16

    // MARK: - Flag bits - verified

    // Bible "Flags" and "Flags2". Verified: only documented bits (plus the
    // undocumented 0x1000 that 340 story missions carry) appear, and
    // Flags2 = 0x0001 ("needs cargo space") sits exactly on missions such
    // as Wild Geese 5b that carry cargo from the start. Several of these
    // bits stop the game offering a mission, which is why they're decoded.
    public var flags: UInt16
    public var flags2: UInt16

    // Flags bits the offer check depends on.
    public static let flagDrainsFuel: UInt16 = 0x0008
    public static let flagNotForCargoShips: UInt16 = 0x2000
    public static let flagNotForWarships: UInt16 = 0x4000

    // Flags2 bit: don't offer without room for the mission cargo.
    public static let flag2NeedsCargoSpace: UInt16 = 0x0001

    // MARK: - Button labels - probable

    // Custom Accept/Refuse button text for the initial mission briefing
    // dialog (falls back to STR# 150's Yes/No/Okay labels when blank).
    // Probable: directly confirmed readable button-label text for several
    // real missions (e.g. "I'm in" / "I need more time",
    // "Sure" / "It's too risky").
    public var acceptButton: String
    public var refuseButton: String

    // MARK: - NCB (Nova Control Bit) expressions - verified

    // Test expression (Bxxx/Pxxx/G/Oxxx/Exxx with &, |, !, parens) that
    // gates the mission's availability. See Nova Bible lines ~106-137 for
    // the test-expression syntax.
    public var availBits: String

    // The six SET expressions (Nova Bible lines ~146-227: Bxxx to
    // set/!Bxxx to clear/^Bxxx to toggle a control bit, plus special
    // operators like Sxxx "start mission xxx automatically", Axxx "abort
    // mission xxx", Fxxx "fail mission xxx"), evaluated when the
    // corresponding player action happens. THIS IS THE MISSION-CHAINING
    // MECHANISM - see startedMissionIDs(in:) and the file doc comment
    // above. Verified: decoded coherently (clean, short, punctuation-and-
    // digit-heavy strings matching the documented grammar exactly, with
    // zero garbage) across every mission checked, including reproducing a
    // full multi-mission real story chain (see MissionDefinitionTests).
    // Constants so the parsed mission-ID lists below can never go stale.
    public let onAccept: String
    public let onRefuse: String
    public let onSuccess: String
    public let onFailure: String
    public let onAbort: String
    public let onShipDone: String

    // Mission IDs this mission will automatically start on each trigger.
    // onSuccess is the primary "leads to the next mission in the story"
    // link; the others cover the less common but still real branching
    // cases (e.g. a refused or failed mission redirecting into a different
    // follow-up). Parsed once here because chain views read them for every
    // row on every redraw.
    public let acceptMissionIDs: [Int]
    public let refuseMissionIDs: [Int]
    public let successMissionIDs: [Int]
    public let failureMissionIDs: [Int]
    public let abortMissionIDs: [Int]
    public let shipDoneMissionIDs: [Int]

    // Every mission ID this mission can chain to, via any trigger, for
    // callers that just want "what could come next" without caring which
    // specific event caused it.
    public let allChainedMissionIDs: [Int]

    public init(
        id: Int,
        name: String,
        availStel: Int16,
        availLoc: Int16,
        availRecord: Int16,
        availRating: Int16,
        availRandom: Int16,
        travelStel: Int16,
        returnStel: Int16,
        cargoType: Int16,
        cargoQty: Int16,
        pickupMode: Int16,
        dropOffMode: Int16,
        scanMask: Int16,
        payVal: Int32,
        shipCount: Int16,
        shipSyst: Int16,
        shipDude: Int16,
        shipGoal: Int16,
        shipBehav: Int16,
        shipNameID: Int16,
        briefText: Int16,
        quickBrief: Int16,
        loadCargText: Int16,
        dumpCargoText: Int16,
        compText: Int16,
        canAbort: Bool,
        timeLimit: Int16,
        dispWeight: Int16,
        acceptButton: String,
        refuseButton: String,
        availBits: String,
        onAccept: String,
        onRefuse: String,
        onSuccess: String,
        onFailure: String,
        onAbort: String,
        onShipDone: String,
        flags: UInt16 = 0,
        flags2: UInt16 = 0
    ) {
        self.id = id
        self.name = name
        self.availStel = availStel
        self.availLoc = availLoc
        self.availRecord = availRecord
        self.availRating = availRating
        self.availRandom = availRandom
        self.travelStel = travelStel
        self.returnStel = returnStel
        self.cargoType = cargoType
        self.cargoQty = cargoQty
        self.pickupMode = pickupMode
        self.dropOffMode = dropOffMode
        self.scanMask = scanMask
        self.payVal = payVal
        self.shipCount = shipCount
        self.shipSyst = shipSyst
        self.shipDude = shipDude
        self.shipGoal = shipGoal
        self.shipBehav = shipBehav
        self.shipNameID = shipNameID
        self.briefText = briefText
        self.quickBrief = quickBrief
        self.loadCargText = loadCargText
        self.dumpCargoText = dumpCargoText
        self.compText = compText
        self.canAbort = canAbort
        self.timeLimit = timeLimit
        self.dispWeight = dispWeight
        self.acceptButton = acceptButton
        self.refuseButton = refuseButton
        self.availBits = availBits
        self.onAccept = onAccept
        self.onRefuse = onRefuse
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        self.onAbort = onAbort
        self.onShipDone = onShipDone
        self.flags = flags
        self.flags2 = flags2

        self.acceptMissionIDs = Self.startedMissionIDs(in: onAccept)
        self.refuseMissionIDs = Self.startedMissionIDs(in: onRefuse)
        self.successMissionIDs = Self.startedMissionIDs(in: onSuccess)
        self.failureMissionIDs = Self.startedMissionIDs(in: onFailure)
        self.abortMissionIDs = Self.startedMissionIDs(in: onAbort)
        self.shipDoneMissionIDs = Self.startedMissionIDs(in: onShipDone)
        self.allChainedMissionIDs = successMissionIDs + failureMissionIDs + refuseMissionIDs + abortMissionIDs + acceptMissionIDs + shipDoneMissionIDs
    }

    // MARK: - Reward description

    // Human-readable interpretation of payVal, covering the Bible's
    // documented special-reward sentinel ranges (see payVal's doc comment
    // above) as well as the plain cash case. The exact government ID packed
    // inside each negative range's formula isn't independently confirmed
    // (see the omissions note at the bottom of this file), so those cases
    // describe the reward's kind rather than naming a specific government.
    public var payDescription: String {
        switch payVal {
        case 0, -1:
            return "No pay"
        case 1...:
            return "\(payVal) credits"
        case -10383...(-10128):
            return "Clean legal record with a government"
        case -20383...(-20128):
            return "Clean legal record with a government and its allies"
        case -30383...(-30128):
            return "Clean legal record with a government and its classmates"
        case -40099...(-40001):
            let percent = -payVal - 40000
            return "Take away \(percent)% of the player's cash"
        case ...(-50000):
            let credits = -payVal - 50000
            return "Take away \(credits) credits at mission start"
        default:
            return "Unknown special reward (\(payVal))"
        }
    }

    // MARK: - Mission chaining

    // Extracts every "Sxxx" (start mission xxx) token's mission ID from an
    // NCB set-expression string, in the order they appear. Set expressions
    // are whitespace-separated tokens, optionally parenthesized (for the
    // "R(op1 op2)" random-choice form) and/or prefixed with `!` (clear) or
    // `^` (toggle) - none of which change which numeric ID an `S` operator
    // targets, so this simply scans for every `S<digits>` substring
    // (case-insensitive) rather than fully parsing the grammar.
    public static func startedMissionIDs(in expression: String) -> [Int] {
        guard !expression.isEmpty else { return [] }

        var result: [Int] = []
        let chars = Array(expression)
        var index = 0

        while index < chars.count {
            let c = chars[index]
            if c == "S" || c == "s" {
                var digitEnd = index + 1
                while digitEnd < chars.count, chars[digitEnd].isNumber {
                    digitEnd += 1
                }
                if digitEnd > index + 1, let value = Int(String(chars[(index + 1)..<digitEnd])) {
                    result.append(value)
                }
                index = digitEnd
            } else {
                index += 1
            }
        }

        return result
    }

    // MARK: - Layout

    // See the file doc comment above for why every one of these offsets is
    // static (no sequential Pascal-string walk needed, unlike shïp/oütf).
    enum Layout {
        static let availStel = 0
        // Bytes 2-3: unknown/reserved, always 0x0000 in all 791 real
        // resources - not exposed (see omissions note below).
        static let availLoc = 4
        static let availRecord = 6
        static let availRating = 8
        static let availRandom = 10
        static let travelStel = 12
        static let returnStel = 14
        static let cargoType = 16
        static let cargoQty = 18
        static let pickupMode = 20
        static let dropOffMode = 22
        static let scanMask = 24
        // Bytes 26-27: unknown/reserved, always 0x0000 - not exposed.
        // PayVal is a 4-byte big-endian Int32 spanning bytes 28-31 (what was
        // previously misread as a 2-byte ShipCount at 28-29 was actually
        // just this field's high 16 bits).
        static let payVal = 28
        static let shipCount = 32
        static let shipSyst = 34
        static let shipDude = 36
        static let shipGoal = 38
        static let shipBehav = 40
        // Bytes 42-45: unidentified - not exposed, see omissions.
        static let shipNameID = 46
        // Bytes 48-51: unidentified - not exposed, see omissions.
        static let briefText = 52
        static let quickBrief = 54
        static let loadCargText = 56
        static let dumpCargoText = 58
        static let compText = 60
        // Bytes 62-63: unidentified (weak FailText candidate, not
        // confident enough to expose) - see omissions.
        static let timeLimit = 64
        static let canAbort = 66
        // Bytes 68-79: probably ShipDoneText, AuxShipCount/Dude/Syst (value
        // patterns fit) - not exposed.
        static let flags = 80
        static let flags2 = 82
        // Bytes 84-87: zero in every stock mission (AvailShipType is likely
        // here, but no stock mission uses it, so it can't be placed).
        // Bytes 88-89: probably RefuseText (desc IDs such as 20800).

        // The seven fixed-width NCB expression slots. Each slot is 255
        // bytes wide; its content (a null-padded ASCII string) starts 2
        // bytes into the slot (the leading 2 bytes are a constant, useless
        // "127" capacity marker - see file doc comment). Content capacity
        // used here (200 bytes) is a safe bound well under the true ~253
        // byte capacity - real expressions are always far shorter.
        static let ncbSlotWidth = 255
        static let ncbFirstContentOffset = 92
        static let ncbContentCapacity = 200

        static let availBitsSlot = 0
        static let onAcceptSlot = 1
        static let onRefuseSlot = 2
        static let onSuccessSlot = 3
        static let onFailureSlot = 4
        static let onAbortSlot = 5
        static let onShipDoneSlot = 6

        static func ncbContentOffset(slot: Int) -> Int {
            ncbFirstContentOffset + slot * ncbSlotWidth
        }

        // After the 7 NCB slots (ending at 90 + 7*255 = 1875) comes the
        // Require pair + DatePostInc (10 bytes, always 0 in real data -
        // not exposed, see omissions), then two 32-byte button-label
        // slots (2-byte marker + up to 30 bytes of null-padded content),
        // then DispWeight.
        static let buttonSlotWidth = 32
        static let acceptButtonContentOffset = 1887
        static let refuseButtonContentOffset = 1887 + buttonSlotWidth
        static let buttonContentCapacity = 28

        static let dispWeight = 1952

        // Real mïsn resources are always exactly this size.
        static let expectedSize = 1970
    }

    // MARK: - Decoding

    public static func decodeAll(from library: GameDataLibrary) -> [MissionDefinition] {
        library.resources(ofType: "mïsn").compactMap { decode(from: $0) }
    }

    // Never throws out to the caller - a malformed or unexpectedly-shaped
    // resource is simply skipped, matching this codebase's defensive-
    // decoding convention (see MissionSlot/OutfitDefinition).
    public static func decode(from resource: GameResource) -> MissionDefinition? {
        let reader = ByteReader(resource.data)

        do {
            let availStel = try reader.int16(at: Layout.availStel, byteOrder: .big)
            let availLoc = try reader.int16(at: Layout.availLoc, byteOrder: .big)
            let availRecord = try reader.int16(at: Layout.availRecord, byteOrder: .big)
            let availRating = try reader.int16(at: Layout.availRating, byteOrder: .big)
            let availRandom = try reader.int16(at: Layout.availRandom, byteOrder: .big)

            let travelStel = try reader.int16(at: Layout.travelStel, byteOrder: .big)
            let returnStel = try reader.int16(at: Layout.returnStel, byteOrder: .big)

            let cargoType = try reader.int16(at: Layout.cargoType, byteOrder: .big)
            let cargoQty = try reader.int16(at: Layout.cargoQty, byteOrder: .big)
            let pickupMode = try reader.int16(at: Layout.pickupMode, byteOrder: .big)
            let dropOffMode = try reader.int16(at: Layout.dropOffMode, byteOrder: .big)
            let scanMask = try reader.int16(at: Layout.scanMask, byteOrder: .big)

            let payVal = try reader.int32(at: Layout.payVal, byteOrder: .big)

            let shipCount = try reader.int16(at: Layout.shipCount, byteOrder: .big)
            let shipSyst = try reader.int16(at: Layout.shipSyst, byteOrder: .big)
            let shipDude = try reader.int16(at: Layout.shipDude, byteOrder: .big)
            let shipGoal = try reader.int16(at: Layout.shipGoal, byteOrder: .big)
            let shipBehav = try reader.int16(at: Layout.shipBehav, byteOrder: .big)
            let shipNameID = try reader.int16(at: Layout.shipNameID, byteOrder: .big)

            let briefText = try reader.int16(at: Layout.briefText, byteOrder: .big)
            let quickBrief = try reader.int16(at: Layout.quickBrief, byteOrder: .big)
            let loadCargText = try reader.int16(at: Layout.loadCargText, byteOrder: .big)
            let dumpCargoText = try reader.int16(at: Layout.dumpCargoText, byteOrder: .big)
            let compText = try reader.int16(at: Layout.compText, byteOrder: .big)

            let canAbort = try reader.int16(at: Layout.canAbort, byteOrder: .big) != 0
            let timeLimit = try reader.int16(at: Layout.timeLimit, byteOrder: .big)
            let dispWeight = try reader.int16(at: Layout.dispWeight, byteOrder: .big)

            let acceptButton = (try? reader.cString(at: Layout.acceptButtonContentOffset, maxLength: Layout.buttonContentCapacity)) ?? ""
            let refuseButton = (try? reader.cString(at: Layout.refuseButtonContentOffset, maxLength: Layout.buttonContentCapacity)) ?? ""

            let availBits = try readNCBExpression(reader, slot: Layout.availBitsSlot)
            let onAccept = try readNCBExpression(reader, slot: Layout.onAcceptSlot)
            let onRefuse = try readNCBExpression(reader, slot: Layout.onRefuseSlot)
            let onSuccess = try readNCBExpression(reader, slot: Layout.onSuccessSlot)
            let onFailure = try readNCBExpression(reader, slot: Layout.onFailureSlot)
            let onAbort = try readNCBExpression(reader, slot: Layout.onAbortSlot)
            let onShipDone = try readNCBExpression(reader, slot: Layout.onShipDoneSlot)

            return MissionDefinition(
                id: resource.id,
                name: resource.name,
                availStel: availStel,
                availLoc: availLoc,
                availRecord: availRecord,
                availRating: availRating,
                availRandom: availRandom,
                travelStel: travelStel,
                returnStel: returnStel,
                cargoType: cargoType,
                cargoQty: cargoQty,
                pickupMode: pickupMode,
                dropOffMode: dropOffMode,
                scanMask: scanMask,
                payVal: payVal,
                shipCount: shipCount,
                shipSyst: shipSyst,
                shipDude: shipDude,
                shipGoal: shipGoal,
                shipBehav: shipBehav,
                shipNameID: shipNameID,
                briefText: briefText,
                quickBrief: quickBrief,
                loadCargText: loadCargText,
                dumpCargoText: dumpCargoText,
                compText: compText,
                canAbort: canAbort,
                timeLimit: timeLimit,
                dispWeight: dispWeight,
                acceptButton: acceptButton,
                refuseButton: refuseButton,
                availBits: availBits,
                onAccept: onAccept,
                onRefuse: onRefuse,
                onSuccess: onSuccess,
                onFailure: onFailure,
                onAbort: onAbort,
                onShipDone: onShipDone,
                flags: UInt16(bitPattern: try reader.int16(at: Layout.flags, byteOrder: .big)),
                flags2: UInt16(bitPattern: try reader.int16(at: Layout.flags2, byteOrder: .big))
            )
        } catch {
            return nil
        }
    }

    private static func readNCBExpression(_ reader: ByteReader, slot: Int) throws -> String {
        let offset = Layout.ncbContentOffset(slot: slot)
        return (try? reader.cString(at: offset, maxLength: Layout.ncbContentCapacity)) ?? ""
    }
}

// MARK: - Honest omissions
//
// Fields documented in the Nova Bible that this first pass could NOT
// confidently locate, after substantial empirical cross-checking against
// all 791 real mission resources (aggregate value-range sweeps, exact
// discrete-value-set matching, sentinel-pattern matching, and specific
// named-mission cross-checks):
//
//   - RESOLVED 2026-09-24: AvailRating, PayVal, and ShipCount were
//     previously misassigned (AvailRating's offset 8 was read as PayVal;
//     ShipCount's offset 28 was actually PayVal's high 16 bits once PayVal
//     was correctly identified as a 4-byte Int32). All three are now
//     verified - see their individual doc comments above for the evidence
//     (named-mission dollar-amount cross-checks for PayVal, threshold-like
//     value distributions for AvailRating, exact discrete range for
//     ShipCount).
//   - ShipStart, CompGovt, CompReward, ShipSubtitle, RefuseText,
//     FailText, ShipDoneText, AvailShipType, AuxShipCount, AuxShipDude,
//     AuxShipSyst, Require (x2), DatePostInc (Flags and Flags2 have since
//     been located at 80/82 - see their doc comment above): several
//     candidate offsets were found with plausible-but-not-conclusive value
//     shapes (see the byte ranges called out as "unidentified" in Layout
//     above), but none had a signature specific enough to confidently
//     assign without risking silently-wrong data. Left undecoded rather
//     than guessed, matching this codebase's established convention (see
//     OutfitDefinition's similar scope limit note).
//   - Two 2-byte spans (offsets 2-3, 26-27) are always exactly 0x0000
//     across all 791 real resources - genuinely unexplained (not
//     documented in the Nova Bible at all); left undecoded.
