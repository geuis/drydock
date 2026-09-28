import XCTest
@testable import Drydock

// Confirms ResourceNameIndex resolves real names from the installed EV Nova
// game data, and that its synthetic constructor (for tests/previews) behaves
// correctly without touching any real files. Skips gracefully via XCTSkip if
// the game install isn't present, matching RezArchiveTests's pattern.
final class ResourceNameIndexTests: XCTestCase {
    // MARK: - Synthetic constructor (no real files needed)

    func testNamesByTypeConstructorResolvesExactMatches() {
        let index = ResourceNameIndex(namesByType: [
            ResourceNameIndex.systems: [128: "Sol", 129: "Alpha Centauri"],
            ResourceNameIndex.persons: [200: "Jack Folstam"]
        ])

        XCTAssertEqual(index.name(type: ResourceNameIndex.systems, id: 128), "Sol")
        XCTAssertEqual(index.name(type: ResourceNameIndex.systems, id: 129), "Alpha Centauri")
        XCTAssertEqual(index.name(type: ResourceNameIndex.persons, id: 200), "Jack Folstam")
    }

    func testNameReturnsNilForUnknownTypeOrID() {
        let index = ResourceNameIndex(namesByType: [ResourceNameIndex.systems: [128: "Sol"]])

        XCTAssertNil(index.name(type: ResourceNameIndex.systems, id: 999))
        XCTAssertNil(index.name(type: ResourceNameIndex.governments, id: 128))
    }

    func testEntriesAreSortedByID() {
        let index = ResourceNameIndex(namesByType: [
            ResourceNameIndex.systems: [130: "Nesre Secundus", 128: "Sol", 129: "Alpha Centauri"]
        ])

        let entries = index.entries(ofType: ResourceNameIndex.systems)
        XCTAssertEqual(entries.map(\.id), [128, 129, 130])
        XCTAssertEqual(entries.map(\.name), ["Sol", "Alpha Centauri", "Nesre Secundus"])
    }

    func testEntriesReturnsEmptyArrayForUnindexedType() {
        let index = ResourceNameIndex(namesByType: [:])
        XCTAssertTrue(index.entries(ofType: ResourceNameIndex.systems).isEmpty)
    }

    // Names are returned exactly as stored, including any ";comment" suffix -
    // stripping that is a caller concern, not this type's.
    func testNamePreservesCommentSuffixesVerbatim() {
        let index = ResourceNameIndex(namesByType: [
            ResourceNameIndex.stellars: [128: "Krim-Hwa Homeworld;internal note"]
        ])

        XCTAssertEqual(index.name(type: ResourceNameIndex.stellars, id: 128), "Krim-Hwa Homeworld;internal note")
    }

    // MARK: - Real game data

    // Every type this index promises to cover should have a plausible,
    // non-trivial resource count - a loose sanity check against the Nova
    // Bible's documented per-type maximums plus the classic Mac resource ID
    // floor of 128, mirroring RezArchiveTests's approach.
    func testIndexedTypesHavePlausibleCountsInRealData() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let index = ResourceNameIndex(library: library)

        let expectedNonEmptyTypes: [(type: String, maxCount: Int)] = [
            (ResourceNameIndex.systems, 2048),
            (ResourceNameIndex.stellars, 1500),
            (ResourceNameIndex.persons, 1000),
            (ResourceNameIndex.ranks, 500),
            (ResourceNameIndex.crons, 2000),
            (ResourceNameIndex.governments, 256),
            (ResourceNameIndex.junk, 100),
            (ResourceNameIndex.disasters, 500)
        ]

        for (type, maxCount) in expectedNonEmptyTypes {
            let entries = index.entries(ofType: type)
            XCTAssertFalse(entries.isEmpty, "Expected at least one '\(type)' resource in real game data")
            XCTAssertLessThanOrEqual(entries.count, maxCount, "'\(type)' produced an implausibly large count: \(entries.count)")

            for entry in entries {
                XCTAssertGreaterThanOrEqual(entry.id, 128, "\(type) resource id \(entry.id) is below the classic-Mac floor of 128")
            }
        }
    }

    // Convenience types (ships/outfits/weapons/missions) should also resolve,
    // matching RezArchiveTests's expected-types list.
    func testConvenienceTypesResolve() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let index = ResourceNameIndex(library: library)

        for type in ["shïp", "oütf", "wëap", "mïsn"] {
            XCTAssertFalse(index.entries(ofType: type).isEmpty, "Expected at least one '\(type)' resource")
        }
    }

    // Cross-checks ResourceNameIndex against GameDataLibrary directly: every
    // real system resource's name should resolve exactly via name(type:id:).
    func testSystemNamesMatchRawLibraryResources() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let index = ResourceNameIndex(library: library)

        let systemResources = library.resources(ofType: ResourceNameIndex.systems)
        guard !systemResources.isEmpty else {
            throw XCTSkip("No sÿst resources in this scenario's data - skipping.")
        }

        for resource in systemResources.prefix(25) {
            XCTAssertEqual(index.name(type: ResourceNameIndex.systems, id: resource.id), resource.name)
        }
    }

    // A well-known EV Nova system, if present in this scenario's data,
    // should resolve to a name containing "Sol".
    func testKnownSystemNameResolves() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let index = ResourceNameIndex(library: library)

        guard let sol = library.resources(ofType: ResourceNameIndex.systems).first(where: { $0.name.localizedCaseInsensitiveContains("Sol") }) else {
            throw XCTSkip("No system named 'Sol' in this scenario's data - skipping.")
        }

        XCTAssertEqual(index.name(type: ResourceNameIndex.systems, id: sol.id), sol.name)
    }
}
