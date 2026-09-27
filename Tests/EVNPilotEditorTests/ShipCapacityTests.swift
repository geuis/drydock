import XCTest
@testable import EVNPilotEditor

// The Geuis case: a Mod Starbridge (20-ton hold) with a Mass Retool (-12
// tons of cargo) has 8 tons free, so Wild Geese 5b (10 tons, "needs cargo
// space") is never offered. Runs against the real game data.
final class ShipCapacityTests: XCTestCase {
    private static let modStarbridgeID = 165
    private static let massRetoolID = 192
    private static let matrixSteelID = 181
    private static let wildGeese5bID = 644

    private struct GameData {
        let ships: [Int: ShipDefinition]
        let outfits: [Int: OutfitDefinition]
        let missions: [MissionDefinition]
    }

    private func loadGameData() throws -> GameData {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/EV Nova/Nova Files", isDirectory: true)

        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("EV Nova game files not found - skipping real-data check.")
        }

        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let ships = Dictionary(ShipDefinition.decodeAll(from: library).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let outfits = Dictionary(OutfitDefinition.decodeAll(from: library).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return GameData(ships: ships, outfits: outfits, missions: MissionDefinition.decodeAll(from: library))
    }

    private func ownedCounts(_ owned: [Int: Int16]) -> [Int16] {
        var counts: [Int16] = [Int16](repeating: 0, count: 512)

        for (outfitID, count) in owned {
            counts[outfitID - PilotStoryState.outfitIDBase] = count
        }

        return counts
    }

    private func capacity(_ data: GameData, owned: [Int: Int16]) throws -> ShipCapacity {
        let ship: ShipDefinition = try XCTUnwrap(data.ships[Self.modStarbridgeID])

        return ShipCapacity(ship: ship, outfitsByID: data.outfits, ownedOutfitCounts: ownedCounts(owned), tradeCargo: [0, 0, 0, 0, 0, 0], missionCargo: 0)
    }

    // MARK: - Ship stock arrays

    func testModStarbridgeStockLoadoutReadsAsInt16Slots() throws {
        let ship: ShipDefinition = try XCTUnwrap(try loadGameData().ships[Self.modStarbridgeID])

        XCTAssertEqual(ship.weapType, [129, 128, 135, -1])
        XCTAssertEqual(ship.weapCount, [3, 2, 2, 0])
        XCTAssertEqual(ship.ammoLoad[2], 20)
        XCTAssertEqual(ship.defaultItems, [238, 239, -1, -1])
        XCTAssertEqual(ship.itemCount, [1, 1, 0, 0])
    }

    // MARK: - Capacity

    func testMassRetoolShrinksTheHold() throws {
        let result: ShipCapacity = try capacity(try loadGameData(), owned: [Self.massRetoolID: 1])

        XCTAssertEqual(result.baseCargo, 20)
        XCTAssertEqual(result.cargoAdjustments.map(\.outfitID), [Self.massRetoolID])
        XCTAssertEqual(result.cargoCapacity, 8)
        XCTAssertEqual(result.freeCargo, 8)
    }

    func testCargoAboardReducesFreeSpace() throws {
        let data = try loadGameData()
        let ship: ShipDefinition = try XCTUnwrap(data.ships[Self.modStarbridgeID])
        let result = ShipCapacity(ship: ship, outfitsByID: data.outfits, ownedOutfitCounts: ownedCounts([:]), tradeCargo: [5, 0, 3, 0, 0, 0], missionCargo: 4)

        XCTAssertEqual(result.cargoAboard, 12)
        XCTAssertEqual(result.freeCargo, 8)
    }

    func testMassRetoolFreesOutfitSpace() throws {
        let data = try loadGameData()
        let without: ShipCapacity = try capacity(data, owned: [:])
        let with: ShipCapacity = try capacity(data, owned: [Self.massRetoolID: 1])

        // Its mass is -10, so installing it leaves 10 more tons for outfits.
        XCTAssertEqual(with.freeMass - without.freeMass, 10)
    }

    func testShipScaledOutfitMassUsesTheShipsMass() throws {
        let data = try loadGameData()
        let matrixSteel: OutfitDefinition = try XCTUnwrap(data.outfits[Self.matrixSteelID])

        // Flag 0x0400 with mass 3 on a 125-ton ship: 125 x 3 / 100.
        XCTAssertNotEqual(matrixSteel.flags & ShipCapacity.massScalesWithShipFlag, 0)
        XCTAssertEqual(ShipCapacity.mass(of: matrixSteel, shipMass: 125), 3)
        XCTAssertEqual(ShipCapacity.mass(of: matrixSteel, shipMass: 400), 12)
    }

    func testFuelTankOutfitsRaiseFuelCapacity() throws {
        let data = try loadGameData()
        let tank: OutfitDefinition = try XCTUnwrap(data.outfits.values.filter { $0.modType == ShipCapacity.fuelCapacityModType && $0.modVal > 0 }.min { $0.id < $1.id })
        let result: ShipCapacity = try capacity(data, owned: [tank.id: 2])

        XCTAssertEqual(result.fuelCapacity, result.baseFuel + 2 * Int(tank.modVal))
    }

    // MARK: - Mission offer checks

    func testWildGeese5bNeedsCargoSpaceFlag() throws {
        let mission: MissionDefinition = try XCTUnwrap(try loadGameData().missions.first { $0.id == Self.wildGeese5bID })

        XCTAssertNotEqual(mission.flags2 & MissionDefinition.flag2NeedsCargoSpace, 0)
        XCTAssertEqual(mission.cargoQty, 10)
    }

    func testMissionBlockedWhenHoldIsTooSmall() throws {
        let data = try loadGameData()
        let mission: MissionDefinition = try XCTUnwrap(data.missions.first { $0.id == Self.wildGeese5bID })
        let ship = PilotShipState(name: "Mod Starbridge", inherentAI: 3, capacity: try capacity(data, owned: [Self.massRetoolID: 1]), fuel: 300)
        let issues: [MissionIssue] = MissionDiagnostics.shipRequirementIssues(for: mission, ship: ship)
        let issue: MissionIssue = try XCTUnwrap(issues.first { $0.id == "ship-cargo-space" })

        XCTAssertEqual(issue.severity, .blocker)
        XCTAssertEqual(issue.title, "Needs 10 tons of free cargo space (you have 8)")
        XCTAssertTrue(issue.detail.contains("Mass Retool -12"), issue.detail)
    }

    func testMissionOfferedWhenHoldIsBigEnough() throws {
        let data = try loadGameData()
        let mission: MissionDefinition = try XCTUnwrap(data.missions.first { $0.id == Self.wildGeese5bID })
        let ship = PilotShipState(name: "Mod Starbridge", inherentAI: 3, capacity: try capacity(data, owned: [:]), fuel: 300)

        XCTAssertTrue(MissionDiagnostics.shipRequirementIssues(for: mission, ship: ship).isEmpty)
    }

    func testCargoShortageMakesAvailableMissionBlocked() throws {
        let data = try loadGameData()
        let storyFlags = StoryFlagCatalog(missions: data.missions, outfits: Array(data.outfits.values), ships: Array(data.ships.values)).flagsByID
        var bits: [Bool] = [Bool](repeating: false, count: 10000)
        bits[814] = true

        let ship = PilotShipState(name: "Mod Starbridge", inherentAI: 3, capacity: try capacity(data, owned: [Self.massRetoolID: 1]), fuel: 300)
        let state = PilotStoryState(bits: bits, outfitCounts: ownedCounts([Self.massRetoolID: 1]), exploration: [Int16](repeating: 0, count: 2048), combatRating: 2419, isMale: true, activeMissionIDs: [], ship: ship)
        let diagnostics = MissionDiagnostics(missions: data.missions, storyFlags: storyFlags, state: state)

        XCTAssertEqual(diagnostics.diagnosis(for: Self.wildGeese5bID)?.status, .blocked)
    }
}
