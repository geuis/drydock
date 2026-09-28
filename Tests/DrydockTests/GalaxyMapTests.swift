import XCTest
@testable import Drydock

// Confirms the sÿst decoder reads real positions, hyperlinks, planets, and
// governments from the installed EV Nova data, and that mission locations
// resolve to systems on the map. Skips via XCTSkip if the game isn't
// installed, matching RezArchiveTests.
final class GalaxyMapTests: XCTestCase {
    private func loadLibrary() throws -> GameDataLibrary {
        try GameDataLibrary(contentsOfDirectory: novaFilesDirectory())
    }

    private func system(named name: String, in galaxy: GalaxyMap) -> StarSystemDefinition? {
        galaxy.systems.first { GameName($0.name).title == name }
    }

    // MARK: - Synthetic data

    func testLinksAreDeduplicatedAndNeighborsWorkFromEitherEnd() {
        let galaxy = GalaxyMap(systems: [
            StarSystemDefinition(id: 128, name: "A", x: 0, y: 0, connectionIDs: [129], stellarIDs: [128], governmentID: nil),
            StarSystemDefinition(id: 129, name: "B", x: 10, y: 0, connectionIDs: [128, 130], stellarIDs: [], governmentID: 130),
            StarSystemDefinition(id: 130, name: "C", x: 20, y: 5, connectionIDs: [], stellarIDs: [129], governmentID: 130)
        ])

        XCTAssertEqual(galaxy.links.count, 2)
        XCTAssertEqual(galaxy.neighborIDs(of: 130), [129])
        XCTAssertEqual(galaxy.neighborIDs(of: 129), [128, 130])
        XCTAssertEqual(galaxy.systemID(containingStellar: 129), 130)
        XCTAssertEqual(galaxy.systemIDs(ownedBy: 130), [129, 130])
        XCTAssertEqual(galaxy.maxX, 20)
    }

    func testSearchIgnoresApostrophesAndCase() {
        let galaxy = GalaxyMap(systems: [
            StarSystemDefinition(id: 128, name: "Nil'nesa", x: 0, y: 0, connectionIDs: [], stellarIDs: [200], governmentID: nil),
            StarSystemDefinition(id: 129, name: "Sol", x: 10, y: 0, connectionIDs: [], stellarIDs: [], governmentID: nil)
        ])
        let names = ResourceNameIndex(namesByType: [ResourceNameIndex.stellars: [200: "Ni\u{2019}ra Station"]])

        for query in ["Nil'nesa", "nilnesa", "NILNESA", "nil'", "nil"] {
            XCTAssertEqual(MapSearchResult.search(query, galaxy: galaxy, names: names).first?.systemID, 128, "Query \(query)")
        }

        // Curly apostrophes in names are ignored too.
        XCTAssertEqual(MapSearchResult.search("nira", galaxy: galaxy, names: names).map(\.id), ["stellar-200"])
        XCTAssertTrue(MapSearchResult.search("'", galaxy: galaxy, names: names).isEmpty)
    }

    // MARK: - Real data

    func testRealNilnesaIsFoundWithoutTheApostrophe() throws {
        let library = try loadLibrary()
        let galaxy = GalaxyMap(library: library)
        let names = ResourceNameIndex(library: library)

        let withApostrophe = MapSearchResult.search("Nil'nesa", galaxy: galaxy, names: names).map(\.id)
        let without = MapSearchResult.search("nilnesa", galaxy: galaxy, names: names).map(\.id)

        XCTAssertFalse(withApostrophe.isEmpty)
        XCTAssertEqual(withApostrophe, without)
    }

    func testRealSystemsDecodeWithSensibleLayout() throws {
        let galaxy = GalaxyMap(library: try loadLibrary())

        XCTAssertGreaterThan(galaxy.systems.count, 300)
        XCTAssertGreaterThan(galaxy.links.count, galaxy.systems.count / 2)

        let sol = try XCTUnwrap(system(named: "Sol", in: galaxy))
        XCTAssertNotNil(sol.governmentID)
        XCTAssertFalse(galaxy.neighborIDs(of: sol.id).isEmpty)

        // Hyperlinked systems sit close together on the map. Wrong position
        // or link offsets would make links as long as any random pair.
        let averageLinkLength: Double = averageDistance(galaxy.links.map { ($0.fromID, $0.toID) }, in: galaxy)
        let everyPair: [(Int, Int)] = zip(galaxy.systems, galaxy.systems.reversed()).map { ($0.id, $1.id) }
        let averagePairDistance: Double = averageDistance(everyPair, in: galaxy)

        XCTAssertLessThan(averageLinkLength * 4, averagePairDistance)
    }

    private func averageDistance(_ pairs: [(Int, Int)], in galaxy: GalaxyMap) -> Double {
        var total: Double = 0

        for (fromID, toID) in pairs {
            guard let from = galaxy.systemsByID[fromID], let to = galaxy.systemsByID[toID] else { continue }
            total += hypot(Double(from.x - to.x), Double(from.y - to.y))
        }

        return total / Double(max(pairs.count, 1))
    }

    func testRealHyperlinksAreMostlyListedByBothEnds() throws {
        let galaxy = GalaxyMap(library: try loadLibrary())
        var oneSided: Int = 0

        for link in galaxy.links {
            let from = try XCTUnwrap(galaxy.systemsByID[link.fromID])
            let to = try XCTUnwrap(galaxy.systemsByID[link.toID])

            if !from.connectionIDs.contains(to.id) || !to.connectionIDs.contains(from.id) {
                oneSided += 1
            }
        }

        // A wrong offset would give near-random, one-sided links.
        XCTAssertLessThan(oneSided, galaxy.links.count / 10)
    }

    // MARK: - Mission locations

    func testRealSpecificPlanetMissionsLandInOneSystem() throws {
        let library = try loadLibrary()
        let galaxy = GalaxyMap(library: library)
        let missions = MissionDefinition.decodeAll(from: library)
        let pinned = missions.filter { (128...2175).contains(Int($0.availStel)) }

        XCTAssertFalse(pinned.isEmpty)

        let unresolved = pinned.filter { MissionMapLocations.stellarCodeSystems($0.availStel, galaxy: galaxy).count != 1 }
        XCTAssertLessThan(unresolved.count, pinned.count / 20, "Unresolved: \(unresolved.prefix(10).map(\.id))")
    }

    func testRealGovernmentMissionsMarkThatGovernmentsSystems() throws {
        let library = try loadLibrary()
        let galaxy = GalaxyMap(library: library)
        let missions = MissionDefinition.decodeAll(from: library)
        let governmentCoded = missions.filter { (10000...10255).contains(Int($0.availStel)) }

        XCTAssertFalse(governmentCoded.isEmpty)

        for mission in governmentCoded {
            XCTAssertFalse(MissionMapLocations.stellarCodeSystems(mission.availStel, galaxy: galaxy).isEmpty, "Mission \(mission.id) (code \(mission.availStel)) marks no systems")
        }
    }

    func testFixturePilotMissionDestinationsAreRealPlanets() throws {
        let library = try loadLibrary()
        let galaxy = GalaxyMap(library: library)

        guard let url = Bundle.module.url(forResource: "Chuck Yeager", withExtension: "plt", subdirectory: "Fixtures") else {
            throw XCTSkip("Fixture not found")
        }

        let slots = MissionSlot.decodeAll(from: try PilotFile(url: url).workingBytes)
        let chosen: [Int16] = slots.filter(\.isActive).flatMap { [$0.travelStel, $0.returnStel] }.filter { $0 >= 128 }

        for stellarID in chosen {
            XCTAssertNotNil(galaxy.systemID(containingStellar: Int(stellarID)), "Stellar \(stellarID) is in no system")
        }
    }

    // The map's "you are here" ring comes from the pilot's last planet.
    @MainActor
    func testFixturePilotLastPlanetIsInASystem() throws {
        let galaxy = GalaxyMap(library: try loadLibrary())

        guard let url = Bundle.module.url(forResource: "Chuck Yeager", withExtension: "plt", subdirectory: "Fixtures") else {
            throw XCTSkip("Fixture not found")
        }

        let pilotFile = try PilotFile(url: url)
        let index = try XCTUnwrap(pilotFile.schemaInt("lastStellar", in: FieldSchema.loadDefault()))

        XCTAssertNotNil(galaxy.systemID(containingStellar: index + 128), "Stellar \(index + 128) is in no system")
    }

    func testRealEarthIsInSol() throws {
        let library = try loadLibrary()
        let galaxy = GalaxyMap(library: library)
        let names = ResourceNameIndex(library: library)

        let earth = try XCTUnwrap(names.entries(ofType: ResourceNameIndex.stellars).first { GameName($0.name).title == "Earth" })
        let systemID = try XCTUnwrap(galaxy.systemID(containingStellar: earth.id))

        XCTAssertEqual(GameName(galaxy.systemsByID[systemID]?.name ?? "").title, "Sol")
    }
}
