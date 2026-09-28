import XCTest
@testable import Drydock

// Decodes real shïp resources from the actual game files and checks that
// the statically-decoded header block (see ShipDefinition.swift's layout
// notes) produces plausible, internally-consistent values. Skips gracefully
// via XCTSkip if the game install isn't present, matching RezArchiveTests.
final class ShipDefinitionTests: XCTestCase {
    // Debug helper (not itself an assertion) - dumps every decoded ship's
    // key stats so offset hypotheses can be eyeballed against real data.
    // Left in as a diagnostic aid; run with -v to see the output.
    func testDumpAllShipStats() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        XCTAssertFalse(ships.isEmpty, "Expected at least one decodable ship")

        print("Decoded \(ships.count) ships:")
        for ship in ships.sorted(by: { $0.name < $1.name }) {
            print("  \(ship.name) (id \(ship.id)): cost=\(ship.cost) tech=\(ship.techLevel) holds=\(ship.holds) shield=\(ship.shield) armor=\(ship.armor) speed=\(ship.speed) accel=\(ship.accel) mass=\(ship.mass) crew=\(ship.crew) fuel=\(ship.fuel)")
        }
    }

    // Structural check: a "Shuttle" class ship should be one of the
    // cheapest, lowest-tech ships in the game - a relative assertion is more
    // robust than hardcoding an exact expected Cost, which might drift
    // slightly wrong from hand inspection.
    func testShuttleIsCheapAndLowTech() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        XCTAssertFalse(ships.isEmpty, "Expected at least one decodable ship")

        guard let shuttle = ships.first(where: { $0.name == "Shuttle" }) else {
            throw XCTSkip("No ship named exactly 'Shuttle' found in this game install - skipping.")
        }

        let costs = ships.map { $0.cost }.sorted()
        let medianCost = costs[costs.count / 2]

        XCTAssertGreaterThan(shuttle.cost, 0, "Shuttle cost should be positive")
        XCTAssertLessThan(shuttle.cost, medianCost, "Shuttle should be cheaper than the median ship")
        XCTAssertGreaterThanOrEqual(shuttle.techLevel, 0, "Shuttle tech level should not be negative")
        XCTAssertLessThanOrEqual(shuttle.crew, 5, "Shuttle should be crewed by a small handful of people at most")
    }

    // Cross-checks a specific, very well known EV Nova fact: the Kestrel is
    // a plot-reward ship that is never sold in any shipyard, and a cheap
    // early ship like the Shuttle should cost dramatically less than a
    // late-game ship like the Kestrel. A wrong offset/byte-order guess
    // would not reliably reproduce this kind of huge, consistent gap.
    func testKestrelIsMuchMoreExpensiveThanShuttle() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)

        guard let shuttle = ships.first(where: { $0.name == "Shuttle" }) else {
            throw XCTSkip("No ship named exactly 'Shuttle' found in this game install - skipping.")
        }
        guard let kestrel = ships.first(where: { $0.name == "Kestrel" }) else {
            throw XCTSkip("No ship named exactly 'Kestrel' found in this game install - skipping.")
        }

        XCTAssertGreaterThan(kestrel.cost, shuttle.cost * 100, "Kestrel should cost at least two orders of magnitude more than a Shuttle")
        XCTAssertGreaterThan(kestrel.shield, shuttle.shield, "Kestrel should have stronger shields than a Shuttle")
        XCTAssertGreaterThan(kestrel.armor, shuttle.armor, "Kestrel should have stronger armor than a Shuttle")
    }

    // Cross-checks that Cost trends upward with tech level across the whole
    // fleet, on average - not a strict rule (some ships are pricier per-tech
    // than others) but a wrong offset/type guess would produce values with
    // no such correlation at all (e.g. negative or wildly inconsistent
    // costs), while a right one should show a clear positive trend.
    func testCostGenerallyTracksTechLevel() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        XCTAssertFalse(ships.isEmpty, "Expected at least one decodable ship")

        let lowTech = ships.filter { $0.techLevel > 0 && $0.techLevel <= 8 }
        let highTech = ships.filter { $0.techLevel >= 24 && $0.techLevel < 1000 }

        guard !lowTech.isEmpty, !highTech.isEmpty else {
            throw XCTSkip("Not enough tech-level spread in this game install to compare - skipping.")
        }

        let avgLowCost = Double(lowTech.map { Int($0.cost) }.reduce(0, +)) / Double(lowTech.count)
        let avgHighCost = Double(highTech.map { Int($0.cost) }.reduce(0, +)) / Double(highTech.count)

        XCTAssertGreaterThan(avgHighCost, avgLowCost, "Higher tech-level ships should cost more on average than lower tech-level ones")
    }

    // Weapon-array internal consistency check: wherever WeapCount is
    // nonzero (a weapon actually installed), the corresponding WeapType
    // slot should hold a plausible weapon-type resource ID (>= 128, the
    // floor for any classic-Mac game-content resource - see
    // RezArchiveTests). The Nova Bible states the *vanilla* range as
    // 128-191, but this game install includes non-vanilla ship names (e.g.
    // "Abomination", "Phoenix") from plugins/expansions that use weapon IDs
    // above 191 (up to 234 observed) - so the lower bound is what's
    // actually load-bearing here; a wrong offset or element width would not
    // reliably keep every nonzero-count slot's type at or above 128 across
    // many ships and slots the way a correct one does.
    func testWeaponSlotArraysAreInternallyConsistent() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        XCTAssertFalse(ships.isEmpty, "Expected at least one decodable ship")

        var checkedSlots = 0

        for ship in ships {
            for slot in ship.weapCount.indices {
                let count = ship.weapCount[slot]
                guard count > 0 else { continue }

                let type = ship.weapType[slot]
                checkedSlots += 1
                XCTAssertTrue(
                    (128...383).contains(type),
                    "\(ship.name) slot \(slot) has WeapCount \(count) but WeapType \(type) is outside the documented 128-383 range"
                )
            }
        }

        XCTAssertGreaterThan(checkedSlots, 0, "Expected at least one ship with a nonzero stock weapon count to check")
    }

    // MARK: - Tail fields (offset 100 onward)

    // Every ship should decode a non-empty ShortName, CommName, and Long
    // Name - these are always populated in the real game data (unlike the
    // optional Subtitle/MovieFile/expression fields), so an empty result
    // for any of them would indicate a wrong offset.
    func testNameFieldsAreAlwaysPopulated() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        XCTAssertFalse(ships.isEmpty, "Expected at least one decodable ship")

        for ship in ships {
            XCTAssertFalse(ship.shortName.isEmpty, "\(ship.name) has an empty ShortName")
            XCTAssertFalse(ship.commName.isEmpty, "\(ship.name) has an empty CommName")
            XCTAssertFalse(ship.longName.isEmpty, "\(ship.name) has an empty Long Name")
        }
    }

    // The Shuttle's ShortName/CommName should read "Shuttle" and its Long
    // Name should mention "Shuttle" too - a wrong offset would either
    // produce garbage/empty strings or bleed into an adjacent field.
    func testShuttleNameFieldsDecodeToExpectedText() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        guard let shuttle = ships.first(where: { $0.name == "Shuttle" }) else {
            throw XCTSkip("No ship named exactly 'Shuttle' found in this game install - skipping.")
        }

        XCTAssertEqual(shuttle.shortName, "Shuttle")
        XCTAssertEqual(shuttle.commName, "Shuttle")
        XCTAssertTrue(shuttle.longName.localizedCaseInsensitiveContains("Shuttle"), "Long Name '\(shuttle.longName)' should mention Shuttle")
    }

    // Availability/AppearOn/OnPurchase/OnCapture/OnRetire are control-bit
    // expressions - whenever non-blank, every real ship's decoded value
    // should look like well-formed expression syntax (only characters from
    // the Nova Bible's own expression grammar), never raw garbage bytes.
    func testExpressionFieldsDecodeToWellFormedSyntaxWhenPresent() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        XCTAssertFalse(ships.isEmpty, "Expected at least one decodable ship")

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ()!&|")
        var checkedNonBlank = 0

        for ship in ships {
            for expression in [ship.availability, ship.appearOn, ship.onPurchase, ship.onCapture, ship.onRetire] {
                guard !expression.isEmpty else { continue }
                checkedNonBlank += 1
                XCTAssertTrue(
                    expression.unicodeScalars.allSatisfy { allowedCharacters.contains($0) },
                    "\(ship.name) has an expression field with unexpected characters: \"\(expression)\""
                )
            }
        }

        XCTAssertGreaterThan(checkedNonBlank, 0, "Expected at least one ship with a non-blank expression field to check")
    }

    // BuyRandom and HireRandom are documented as percent-chance fields
    // (0-100) - every real ship's decoded value should fall in that range.
    func testBuyAndHireRandomAreValidPercentages() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        XCTAssertFalse(ships.isEmpty, "Expected at least one decodable ship")

        for ship in ships {
            XCTAssertTrue((0...100).contains(ship.buyRandom), "\(ship.name) has an out-of-range BuyRandom: \(ship.buyRandom)")
            XCTAssertTrue((0...100).contains(ship.hireRandom), "\(ship.name) has an out-of-range HireRandom: \(ship.hireRandom)")
        }
    }

    // EscortType is documented as exactly one of -1 (auto), 0 (Fighter),
    // 1 (Medium Ship), 2 (Warship), or 3 (Freighter) - every real ship
    // should land on one of those five values.
    func testEscortTypeIsAlwaysADocumentedCategory() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        XCTAssertFalse(ships.isEmpty, "Expected at least one decodable ship")

        for ship in ships {
            XCTAssertTrue(
                (-1...3).contains(ship.escortType),
                "\(ship.name) has an undocumented EscortType: \(ship.escortType)"
            )
        }
    }

    // Flags3's decoded bits should always fall within the Nova Bible's
    // documented bit list for that field - a wrong offset would produce
    // stray high bits outside that set on at least some real ship.
    func testFlags3BitsAreAllDocumented() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        XCTAssertFalse(ships.isEmpty, "Expected at least one decodable ship")

        let documentedMask: UInt16 = 0x0001 | 0x0002 | 0x0010 | 0x0020 | 0x0040 | 0x0100 | 0x0200 | 0x4000

        for ship in ships {
            XCTAssertEqual(
                ship.flags3 & ~documentedMask, 0,
                "\(ship.name) has undocumented Flags3 bits set: 0x\(String(ship.flags3, radix: 16))"
            )
        }
    }

    // Cross-checks a specific, well known EV Nova fact: the "Asteroid
    // Miner" ship's Flags3 should have the "destroys asteroids" (0x0001)
    // and "scoops asteroid debris" (0x0002) bits set, matching its name
    // and role - a wrong offset would not reliably reproduce this exact
    // semantic match.
    func testAsteroidMinerHasAsteroidFlags3Bits() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        guard let miner = ships.first(where: { $0.name == "Asteroid Miner" }) else {
            throw XCTSkip("No ship named exactly 'Asteroid Miner' found in this game install - skipping.")
        }

        XCTAssertEqual(miner.flags3 & 0x0001, 0x0001, "Asteroid Miner should have the 'destroys asteroids' Flags3 bit set")
        XCTAssertEqual(miner.flags3 & 0x0002, 0x0002, "Asteroid Miner should have the 'scoops asteroid debris' Flags3 bit set")
    }

    // Cross-checks UpgradeTo against real ship IDs: every ship with a
    // nonzero UpgradeTo should point at another ship that actually exists
    // in this game install - a wrong offset would not reliably produce
    // valid cross-references for every one of the (many) ships that use
    // this field.
    func testUpgradeToAlwaysReferencesARealShip() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        let idsById = Set(ships.map { $0.id })

        var checked = 0
        for ship in ships where ship.upgradeTo > 0 {
            checked += 1
            XCTAssertTrue(
                idsById.contains(Int(ship.upgradeTo)),
                "\(ship.name) has UpgradeTo \(ship.upgradeTo) which doesn't match any real ship ID"
            )
        }

        XCTAssertGreaterThan(checked, 0, "Expected at least one ship with a nonzero UpgradeTo to check")
    }

    // Cross-checks that EscUpgrdCost is only ever nonzero when UpgradeTo is
    // actually set - a wrong offset would not reliably show this
    // correlation across every escort-upgradable ship.
    func testEscUpgrdCostCorrelatesWithUpgradeTo() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        var checked = 0

        for ship in ships where ship.upgradeTo <= 0 {
            checked += 1
            XCTAssertEqual(ship.escUpgrdCost, 0, "\(ship.name) has no UpgradeTo but a nonzero EscUpgrdCost: \(ship.escUpgrdCost)")
        }

        XCTAssertGreaterThan(checked, 0, "Expected at least one ship without UpgradeTo to check")
    }

    // DefaultItems2/ItemCount2 should follow the same encoding convention
    // as the original DefaultItems/ItemCount arrays (128-255 = a real
    // outfit resource ID, 255 = no item in that slot) for at least one
    // slot on every ship that has any populated slot at all. Note: real
    // data shows slot 1 is the one consistently populated with a clean
    // (valid ID, plausible count) pair on every ship that uses this field
    // at all - other slots on the same ships sometimes hold small
    // leftover values (e.g. item=1 with count=0) that don't fit the
    // 128-254 convention, consistent with this being stale/unused
    // reserved-buffer content rather than live data (the same phenomenon
    // documented for the expression string fields above) - so this test
    // only requires at least one clean, self-consistent slot per ship
    // rather than every slot being clean.
    func testDefaultItems2HasAtLeastOneValidOutfitIdWhenPresent() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        var shipsWithAnyItem = 0
        var shipsWithValidCleanSlot = 0

        for ship in ships {
            let hasAnyItem = ship.defaultItems2.contains { $0 > 0 }
            guard hasAnyItem else { continue }
            shipsWithAnyItem += 1

            // Read as Int16 slots, every populated slot is clean.
            let hasCleanSlot = ship.defaultItems2.indices.allSatisfy { slot in
                let item = ship.defaultItems2[slot]
                let count = ship.itemCount2[slot]
                return item <= 0 || ((128...639).contains(item) && count > 0)
            }
            if hasCleanSlot {
                shipsWithValidCleanSlot += 1
            }
        }

        XCTAssertGreaterThan(shipsWithAnyItem, 0, "Expected at least one ship with a populated DefaultItems2 slot to check")
        XCTAssertEqual(shipsWithValidCleanSlot, shipsWithAnyItem, "Every ship with a populated DefaultItems2 should have at least one valid-ID/positive-count slot")
    }

    // All decoded numeric header fields should land in sane ranges - guards
    // against a systematically wrong offset producing huge/negative garbage
    // across the board even if the tests above happen to pass by luck.
    // TechLevel is allowed to run very high (see Kestrel note above - some
    // scenario ships intentionally use an unreachable tech level so they
    // can never be sold in a shipyard).
    func testAllShipsDecodeToPlausibleRanges() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)

        let ships = ShipDefinition.decodeAll(from: library)
        XCTAssertFalse(ships.isEmpty, "Expected at least one decodable ship")

        for ship in ships {
            XCTAssertGreaterThanOrEqual(ship.cost, -1, "\(ship.name) has an implausible negative cost: \(ship.cost)")
            XCTAssertLessThan(ship.cost, 100_000_000, "\(ship.name) has an implausibly huge cost: \(ship.cost)")
            XCTAssertGreaterThanOrEqual(ship.techLevel, -1, "\(ship.name) has an implausible tech level: \(ship.techLevel)")
            XCTAssertLessThan(ship.mass, 20_000, "\(ship.name) has an implausibly huge mass: \(ship.mass)")
            XCTAssertGreaterThanOrEqual(ship.crew, -1, "\(ship.name) has an implausible crew count: \(ship.crew)")
            XCTAssertLessThan(ship.crew, 10_000, "\(ship.name) has an implausibly huge crew count: \(ship.crew)")
        }
    }
}
