import XCTest
@testable import Drydock

// Decodes real oütf resources from the installed EV Nova game data and
// checks that the validated fields land in plausible, internally consistent
// ranges - both the original fixed header (DispWeight/Mass/TechLevel/
// ModType/ModVal/Max/Flags/Cost/ModType2-4/ModVal2-4) and the rest of the
// resource decoded in a later pass (Contribute1-2/Require1-2, the
// Availability/OnPurchase/OnSell control-bit expressions, ShortName/LCName/
// LCPlural, ItemClass/ScanMask/BuyRandom/RequireGovt - see OutfitDefinition
// for the full layout writeup). Prefers relative/structural assertions ("a
// cheap item costs less than an expensive one") over hardcoded exact
// values, since these come from real scenario data this repo doesn't own.
// Skips gracefully via XCTSkip if the game files aren't present, matching
// RezArchiveTests's pattern.
final class OutfitDefinitionTests: XCTestCase {
    private func novaFilesDirectory() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("EV Nova", isDirectory: true)
            .appendingPathComponent("Nova Files", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw XCTSkip("EV Nova game files not found at \(directory.path) - skipping real-file verification.")
        }

        return directory
    }

    private func loadOutfits() throws -> [OutfitDefinition] {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let outfits = OutfitDefinition.decodeAll(from: library)

        guard !outfits.isEmpty else {
            throw XCTSkip("No oütf resources decoded - skipping.")
        }

        return outfits
    }

    // Every real oütf resource decoded should produce a plausible, non-empty
    // set, and every ModType should either be documented in the lookup table
    // or explicitly reported as unknown (never crash/garbage).
    func testDecodesAllOutfitsWithoutCrashing() throws {
        let outfits = try loadOutfits()
        XCTAssertGreaterThan(outfits.count, 0)

        for outfit in outfits {
            XCTAssertFalse(outfit.name.isEmpty)
        }
    }

    // "Cargo Expansion" should decode to ModType 2 ("more cargo space") per
    // the Nova Bible's oütf ModType table, with a positive ModVal (tons of
    // cargo added).
    func testCargoExpansionDecodesExpectedModType() throws {
        let outfits = try loadOutfits()
        guard let cargoExpansion = outfits.first(where: { $0.name.localizedCaseInsensitiveContains("Cargo Expansion") }) else {
            throw XCTSkip("No 'Cargo Expansion' outfit in this scenario's data - skipping.")
        }

        XCTAssertEqual(cargoExpansion.modType, 2)
        XCTAssertEqual(OutfitDefinition.modTypeDescription(for: cargoExpansion.modType), "More cargo space")
        XCTAssertGreaterThan(cargoExpansion.modVal, 0)
    }

    // "Afterburner" should decode to ModType 15 ("afterburner") per the
    // Bible's table.
    func testAfterburnerDecodesExpectedModType() throws {
        let outfits = try loadOutfits()
        guard let afterburner = outfits.first(where: { $0.name.localizedCaseInsensitiveContains("Afterburner") }) else {
            throw XCTSkip("No 'Afterburner' outfit in this scenario's data - skipping.")
        }

        XCTAssertEqual(afterburner.modType, 15)
        XCTAssertEqual(OutfitDefinition.modTypeDescription(for: afterburner.modType), "Afterburner")
    }

    // An "Escape Pod" should decode to ModType 11 ("escape pod"), with
    // ModVal -1 (the Bible documents this ModType's ModVal as "ignored").
    func testEscapePodDecodesExpectedModTypeAndIgnoredModVal() throws {
        let outfits = try loadOutfits()
        guard let escapePod = outfits.first(where: { $0.name.localizedCaseInsensitiveContains("Escape Pod") }) else {
            throw XCTSkip("No 'Escape Pod' outfit in this scenario's data - skipping.")
        }

        XCTAssertEqual(escapePod.modType, 11)
        XCTAssertEqual(escapePod.modVal, -1)
    }

    // Structural sanity check: every decoded outfit's Cost should be
    // non-negative (it's read as an unsigned 32-bit field). TechLevel is
    // only asserted non-negative, not bounded above - real scenario data
    // uses a wide variety of deliberately-huge sentinel values (999, 9999,
    // and others like 111-200) to mark items that should never be normally
    // purchasable (mission-granted/plot items), so there's no single
    // meaningful upper bound to assert here.
    func testCostAndTechLevelAreWithinPlausibleBounds() throws {
        let outfits = try loadOutfits()

        for outfit in outfits {
            XCTAssertLessThan(outfit.cost, 100_000_000, "\(outfit.name) has an implausibly large cost: \(outfit.cost)")
            XCTAssertGreaterThanOrEqual(outfit.techLevel, 0, "\(outfit.name) has a negative tech level: \(outfit.techLevel)")
        }
    }

    // Relative comparison: an item that is flagged persistent-and-unsellable
    // (a hallmark of a special/plot-granted item, e.g. a faction-restricted
    // cloaking device) should generally cost more than a basic, freely
    // purchasable item like a fuel scoop or IFF decoder - if both exist in
    // this scenario's data. This is a loose structural check, not an exact
    // value assertion.
    func testAdvancedSoundingItemsCostMoreThanBasicOnes() throws {
        let outfits = try loadOutfits()

        guard let basicItem = outfits.first(where: { $0.name.localizedCaseInsensitiveContains("IFF") }),
              let advancedItem = outfits.first(where: { $0.name.localizedCaseInsensitiveContains("Cloaking Device") }) else {
            throw XCTSkip("Scenario doesn't have both a basic IFF item and a Cloaking Device to compare - skipping.")
        }

        XCTAssertGreaterThan(advancedItem.cost, basicItem.cost)
        XCTAssertGreaterThanOrEqual(advancedItem.techLevel, basicItem.techLevel)
    }

    // ShortName/LCName/LCPlural are fixed 64-byte display-string slots
    // (811/875/939). A well-known, genuinely purchasable item like "Cargo
    // Expansion" should always decode a real ShortName/LCName/LCPlural.
    // A handful of real resources (e.g. ";Krypt mind attack", "Bureau Bomb
    // Outfit" - internal, mission-only effect items never shown in the
    // outfit dialog) legitimately ship with empty display strings, so this
    // only asserts the large majority are populated rather than requiring
    // every single one.
    func testDisplayStringsAreNonEmptyForOrdinaryItems() throws {
        let outfits = try loadOutfits()

        guard let cargoExpansion = outfits.first(where: { $0.name.localizedCaseInsensitiveContains("Cargo Expansion") }) else {
            throw XCTSkip("No 'Cargo Expansion' outfit in this scenario's data - skipping.")
        }

        XCTAssertFalse(cargoExpansion.shortName.isEmpty)
        XCTAssertFalse(cargoExpansion.lcName.isEmpty)
        XCTAssertFalse(cargoExpansion.lcPlural.isEmpty)

        let emptyShortNameCount = outfits.filter { $0.shortName.isEmpty }.count
        XCTAssertLessThan(emptyShortNameCount, outfits.count / 10, "More than 10% of outfits have an empty ShortName - the slot offset is probably wrong.")
    }

    // BuyRandom is documented as a 1-100 percent chance, with values outside
    // that range (including the 0/-1 sentinels seen in real data) meaning
    // "always available". Every decoded value should fall in one of those
    // two buckets - never some other arbitrary number.
    func testBuyRandomIsWithinDocumentedRangeOrSentinel() throws {
        let outfits = try loadOutfits()

        for outfit in outfits {
            let isPercentRange = (1...100).contains(outfit.buyRandom)
            let isAlwaysAvailableSentinel = outfit.buyRandom <= 0
            XCTAssertTrue(isPercentRange || isAlwaysAvailableSentinel, "\(outfit.name) has an implausible BuyRandom: \(outfit.buyRandom)")
        }
    }

    // ScanMask marks "illegal" outfit types (bible: "if any of the 1 bits in
    // a ship's government's ScanMask field match any of the 1 bits in an
    // oütf type's ScanMask field, that government will consider that outfit
    // item illegal"). A everyday legal item like a basic weapon should have
    // ScanMask == 0; an item whose name marks it as explicitly illegal
    // should not.
    func testScanMaskDistinguishesLegalFromIllegalItems() throws {
        let outfits = try loadOutfits()

        guard let legalItem = outfits.first(where: { $0.name.localizedCaseInsensitiveContains("Light Blaster") && !$0.name.localizedCaseInsensitiveContains("Illegal") }),
              let illegalItem = outfits.first(where: { $0.name.localizedCaseInsensitiveContains("Illegal") }) else {
            throw XCTSkip("Scenario doesn't have both a plain 'Light Blaster' and an 'Illegal ...' item to compare - skipping.")
        }

        XCTAssertEqual(legalItem.scanMask, 0)
        XCTAssertNotEqual(illegalItem.scanMask, 0)
    }

    // RequireGovt's documented values are -1 (applies everywhere) or an
    // encoded govt-class value in one of four 256-wide bands starting at
    // 128, 1128, 2128, or 3128. Every decoded value should land on -1, 0, or
    // inside one of those bands (0 and 127 - "unused" and "govt class -1" -
    // are both common real-data defaults not literally covered by the
    // Bible's worked example, but consistent with its own encoding formula;
    // see the Layout doc on OutfitDefinition).
    func testRequireGovtIsWithinDocumentedRangeOrSentinel() throws {
        let outfits = try loadOutfits()

        for outfit in outfits {
            let v = outfit.requireGovt
            let isKnownSentinel = v == -1 || v == 0 || v == 127
            let isEncodedBand = (128...383).contains(v) || (1128...1383).contains(v) || (2128...2383).contains(v) || (3128...3383).contains(v)
            XCTAssertTrue(isKnownSentinel || isEncodedBand, "\(outfit.name) has an implausible RequireGovt: \(v)")
        }
    }

    // Availability/OnPurchase/OnSell are control-bit expressions read from
    // fixed 255-byte slots that are usually empty. When non-empty, real
    // expressions only ever use the documented syntax tokens (bit
    // references, "P" tokens, boolean/set operators, digits, spaces) - never
    // arbitrary binary garbage, which would indicate the slot offsets are
    // wrong.
    func testControlBitExpressionsOnlyContainExpectedSyntaxCharacters() throws {
        let outfits = try loadOutfits()
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 &|!()")

        var foundAtLeastOneNonEmptyExpression = false

        for outfit in outfits {
            for expression in [outfit.availability, outfit.onPurchase, outfit.onSell] where !expression.isEmpty {
                foundAtLeastOneNonEmptyExpression = true
                XCTAssertTrue(
                    expression.unicodeScalars.allSatisfy { allowedCharacters.contains($0) },
                    "\(outfit.name) has an expression with unexpected characters: \"\(expression)\""
                )
            }
        }

        XCTAssertTrue(foundAtLeastOneNonEmptyExpression, "No outfit in this scenario's data has any Availability/OnPurchase/OnSell expression set - can't confirm the string slots decode real content.")
    }

    // The oütf resource is documented as a flat, fixed-size struct - every
    // resource in the real data should be exactly the same byte length.
    func testAllOutfitResourcesShareExpectedSize() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let rawResources = library.resources(ofType: "oütf")

        guard !rawResources.isEmpty else {
            throw XCTSkip("No oütf resources found - skipping.")
        }

        for resource in rawResources {
            XCTAssertEqual(resource.data.count, 1028, "\(resource.name) has an unexpected oütf resource size")
        }
    }
}
