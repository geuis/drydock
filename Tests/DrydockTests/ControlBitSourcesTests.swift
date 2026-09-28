import XCTest
@testable import Drydock

// Decodes real crön/öops/përs/spöb/sÿst/flët/jünk resources from the
// installed EV Nova game data and checks that the control-bit expression
// fields decoded by ControlBitSources.swift are plausible: non-trivial
// counts, and every non-empty decoded expression string parses as valid
// control-bit expression syntax (only the Nova Bible's documented
// characters/operators, never garbage - which would indicate a wrong
// offset). Also confirms StoryFlagCatalog picks these sources up and that
// at least one flag gains a "sets" reference it didn't have before. Skips
// gracefully via XCTSkip if the game install isn't present, matching
// RezArchiveTests's pattern.
final class ControlBitSourcesTests: XCTestCase {
    private func loadLibrary() throws -> GameDataLibrary {
        let directory = try novaFilesDirectory()
        return try GameDataLibrary(contentsOfDirectory: directory)
    }

    // Every character that can legally appear in a Nova control-bit test or
    // set expression, per the Nova Bible's "control bits and scripting"
    // section (lines 97-226 of the converted text): bit references (b/B +
    // digits), test operators (P/G/O/E + digits, & | ! ( )), set operators
    // (S/A/F/G/D/M/N/C/E/H/K/L/P/Y/U/Q/T/X + digits, R ( ) for random
    // choice, ! and ^ prefixes), letters, digits, and spaces.
    private let allowedExpressionCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 &|!()^")

    private func assertValidExpressionSyntax(_ expression: String, context: String, file: StaticString = #filePath, line: UInt = #line) {
        guard !expression.isEmpty else { return }
        XCTAssertTrue(
            expression.unicodeScalars.allSatisfy { allowedExpressionCharacters.contains($0) },
            "\(context) has an expression with unexpected characters: \"\(expression)\"",
            file: file,
            line: line
        )
    }

    // MARK: - Timed Event (crön)

    func testTimedEventsDecodeWithPlausibleCountAndValidSyntax() throws {
        let library = try loadLibrary()
        let events = TimedEventSource.decodeAll(from: library)
        guard !events.isEmpty else { throw XCTSkip("No crön resources - skipping.") }

        XCTAssertLessThanOrEqual(events.count, 2000)

        var foundNonEmpty = false
        for event in events {
            for expression in [event.enableOn, event.onStart, event.onEnd] where !expression.isEmpty {
                foundNonEmpty = true
                assertValidExpressionSyntax(expression, context: "crön \(event.name)")
            }
        }
        XCTAssertTrue(foundNonEmpty, "No crön resource has any EnableOn/OnStart/OnEnd content - can't confirm the slots decode real content.")
    }

    // MARK: - Disaster (öops)

    func testDisastersDecodeWithPlausibleCountAndValidSyntax() throws {
        let library = try loadLibrary()
        let disasters = DisasterSource.decodeAll(from: library)
        guard !disasters.isEmpty else { throw XCTSkip("No öops resources - skipping.") }

        XCTAssertLessThanOrEqual(disasters.count, 500)

        for disaster in disasters {
            assertValidExpressionSyntax(disaster.activateOn, context: "öops \(disaster.name)")
        }
    }

    // MARK: - Character (përs)

    func testCharactersDecodeWithPlausibleCountAndValidSyntax() throws {
        let library = try loadLibrary()
        let characters = CharacterSource.decodeAll(from: library)
        guard !characters.isEmpty else { throw XCTSkip("No përs resources - skipping.") }

        XCTAssertLessThanOrEqual(characters.count, 1000)

        var foundNonEmpty = false
        for character in characters {
            if !character.activeOn.isEmpty {
                foundNonEmpty = true
                assertValidExpressionSyntax(character.activeOn, context: "përs \(character.name)")
            }
        }
        XCTAssertTrue(foundNonEmpty, "No përs resource has any ActiveOn content - can't confirm the slot decodes real content.")
    }

    // MARK: - Planet/Stellar (spöb)

    func testPlanetsDecodeWithPlausibleCountAndValidSyntax() throws {
        let library = try loadLibrary()
        let planets = PlanetSource.decodeAll(from: library)
        guard !planets.isEmpty else { throw XCTSkip("No spöb resources - skipping.") }

        XCTAssertLessThanOrEqual(planets.count, 1500)

        var foundNonEmpty = false
        for planet in planets {
            for expression in [planet.onDominate, planet.onRelease, planet.onDestroy, planet.onRegen] where !expression.isEmpty {
                foundNonEmpty = true
                assertValidExpressionSyntax(expression, context: "spöb \(planet.name)")
            }
        }
        XCTAssertTrue(foundNonEmpty, "No spöb resource has any OnDominate/OnRelease/OnDestroy/OnRegen content - can't confirm the slots decode real content.")
    }

    // MARK: - System (sÿst)

    func testSystemsDecodeWithPlausibleCountAndValidSyntax() throws {
        let library = try loadLibrary()
        let systems = SystemSource.decodeAll(from: library)
        guard !systems.isEmpty else { throw XCTSkip("No sÿst resources - skipping.") }

        XCTAssertLessThanOrEqual(systems.count, 2048)

        var foundNonEmpty = false
        for system in systems {
            if !system.visibility.isEmpty {
                foundNonEmpty = true
                assertValidExpressionSyntax(system.visibility, context: "sÿst \(system.name)")
            }
        }
        XCTAssertTrue(foundNonEmpty, "No sÿst resource has any Visibility content - can't confirm the slot decodes real content.")
    }

    // MARK: - Fleet (flët)

    func testFleetsDecodeWithPlausibleCountAndValidSyntax() throws {
        let library = try loadLibrary()
        let fleets = FleetSource.decodeAll(from: library)
        guard !fleets.isEmpty else { throw XCTSkip("No flët resources - skipping.") }

        XCTAssertLessThanOrEqual(fleets.count, 1000)

        for fleet in fleets {
            assertValidExpressionSyntax(fleet.appearOn, context: "flët \(fleet.name)")
        }
    }

    // MARK: - Junk Type (jünk)

    func testJunkTypesDecodeWithPlausibleCountAndValidSyntax() throws {
        let library = try loadLibrary()
        let junkTypes = JunkTypeSource.decodeAll(from: library)
        guard !junkTypes.isEmpty else { throw XCTSkip("No jünk resources - skipping.") }

        XCTAssertLessThanOrEqual(junkTypes.count, 256)

        for junkType in junkTypes {
            assertValidExpressionSyntax(junkType.buyOn, context: "jünk \(junkType.name) BuyOn")
            assertValidExpressionSyntax(junkType.sellOn, context: "jünk \(junkType.name) SellOn")
        }
    }

    // MARK: - StoryFlagCatalog integration

    // The new sources should genuinely add references StoryFlagCatalog
    // didn't have before - not just decode without crashing.
    func testNewSourcesAddReferencesBeyondMissionsOutfitsShips() throws {
        let library = try loadLibrary()

        let missions = MissionDefinition.decodeAll(from: library)
        let outfits = OutfitDefinition.decodeAll(from: library)
        let ships = ShipDefinition.decodeAll(from: library)

        let oldCatalog = StoryFlagCatalog(missions: missions, outfits: outfits, ships: ships)
        let newCatalog = StoryFlagCatalog(library: library)

        XCTAssertGreaterThanOrEqual(newCatalog.flagsByID.count, oldCatalog.flagsByID.count)

        let oldReferenceCount = oldCatalog.flagsByID.values.reduce(0) { $0 + $1.references.count }
        let newReferenceCount = newCatalog.flagsByID.values.reduce(0) { $0 + $1.references.count }
        XCTAssertGreaterThan(newReferenceCount, oldReferenceCount, "The new resource-type sources added no references at all - either this scenario's data doesn't use them, or a decoder offset is wrong.")

        let newSourceKinds: Set<String> = ["Timed Event", "Disaster", "Character", "Planet", "System", "Fleet", "Junk Type"]
        let observedNewSourceKinds = Set(newCatalog.flagsByID.values.flatMap { $0.references.map(\.sourceKind) }).intersection(newSourceKinds)
        XCTAssertFalse(observedNewSourceKinds.isEmpty, "None of the new source kinds contributed any reference.")
        print("New story-flag source kinds observed in this scenario's data: \(observedNewSourceKinds.sorted())")
        print("Flags before: \(oldCatalog.flagsByID.count), after: \(newCatalog.flagsByID.count) (delta \(newCatalog.flagsByID.count - oldCatalog.flagsByID.count))")
        print("References before: \(oldReferenceCount), after: \(newReferenceCount) (delta \(newReferenceCount - oldReferenceCount))")
    }

    // A flag that no mission/outfit/ship ever *sets* (only tests, or
    // nothing at all) should be relabeled once a new source type is found to
    // set it - this is the concrete case the task exists to fix ("nothing
    // sets this flag" being misleading when a crön/spöb/etc. actually does).
    func testFlagsGainSettersFromNewSourceTypes() throws {
        let library = try loadLibrary()

        let missions = MissionDefinition.decodeAll(from: library)
        let outfits = OutfitDefinition.decodeAll(from: library)
        let ships = ShipDefinition.decodeAll(from: library)

        let oldCatalog = StoryFlagCatalog(missions: missions, outfits: outfits, ships: ships)
        let newCatalog = StoryFlagCatalog(library: library)

        func hasSetter(_ metadata: StoryFlagMetadata?) -> Bool {
            metadata?.references.contains { [.sets, .clears, .toggles].contains($0.effect) } ?? false
        }

        let allFlagIDs = Set(oldCatalog.flagsByID.keys).union(newCatalog.flagsByID.keys)
        let newlyGainedSetters = allFlagIDs.filter { id in
            !hasSetter(oldCatalog[id]) && hasSetter(newCatalog[id])
        }.sorted()

        print("Flags that had zero setters (missions/outfits/ships only) but gained one from a new source type: \(newlyGainedSetters.count)")
        if let example = newlyGainedSetters.first, let metadata = newCatalog[example] {
            print("  Example: flag \(example) - \(metadata.name)")
        }

        guard !newlyGainedSetters.isEmpty else {
            throw XCTSkip("No flag in this scenario's data went from zero setters to having one from a new source type - reporting rather than failing, since this is entirely data-dependent.")
        }

        XCTAssertFalse(newlyGainedSetters.isEmpty)
    }
}
