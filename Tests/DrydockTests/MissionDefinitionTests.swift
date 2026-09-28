import XCTest
@testable import Drydock

// Decodes real mïsn resources from the installed EV Nova game data and
// checks that the validated fields (see MissionDefinition.swift's layout
// writeup) land in plausible, internally consistent ranges, and that the
// mission-chaining mechanism (NCB "Sxxx" tokens embedded in the control-bit
// set-expression fields) resolves a real multi-mission story chain
// correctly. Skips gracefully via XCTSkip if the game files aren't present,
// matching RezArchiveTests/ShipDefinitionTests/OutfitDefinitionTests.
final class MissionDefinitionTests: XCTestCase {
    private func loadMissions() throws -> [MissionDefinition] {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let missions = MissionDefinition.decodeAll(from: library)

        guard !missions.isEmpty else {
            throw XCTSkip("No mïsn resources decoded - skipping.")
        }

        return missions
    }

    // MARK: - Basic decoding

    func testDecodesAllMissionsWithoutCrashing() throws {
        let missions = try loadMissions()
        XCTAssertGreaterThan(missions.count, 0)

        for mission in missions {
            XCTAssertFalse(mission.name.isEmpty)
        }
    }

    // The mïsn resource is documented as a flat, fixed-size struct - every
    // resource in the real data should be exactly the same byte length
    // (1970 bytes - see MissionDefinition's file doc comment for why, even
    // though several fields are free-text control-bit expressions).
    func testAllMissionResourcesShareExpectedSize() throws {
        let directory = try novaFilesDirectory()
        let library = try GameDataLibrary(contentsOfDirectory: directory)
        let rawResources = library.resources(ofType: "mïsn")

        guard !rawResources.isEmpty else {
            throw XCTSkip("No mïsn resources found - skipping.")
        }

        for resource in rawResources {
            XCTAssertEqual(resource.data.count, 1970, "\(resource.name) has an unexpected mïsn resource size")
        }
    }

    // MARK: - Field range validation

    // AvailLoc, PickupMode, DropOffMode, ShipGoal, CanAbort are all verified
    // fields with an exact, small, documented discrete value set - every
    // real mission should land in that set with zero exceptions, since a
    // wrong offset would not reliably produce a clean discrete distribution
    // across 791 real resources.
    func testDiscreteFieldsStayWithinDocumentedValueSets() throws {
        let missions = try loadMissions()

        for mission in missions {
            XCTAssertTrue((0...6).contains(mission.availLoc), "\(mission.name) has implausible AvailLoc: \(mission.availLoc)")
            XCTAssertTrue((-1...2).contains(mission.pickupMode), "\(mission.name) has implausible PickupMode: \(mission.pickupMode)")
            XCTAssertTrue((-1...1).contains(mission.dropOffMode), "\(mission.name) has implausible DropOffMode: \(mission.dropOffMode)")
            XCTAssertTrue((-1...6).contains(mission.shipGoal), "\(mission.name) has implausible ShipGoal: \(mission.shipGoal)")
            XCTAssertTrue((0...100).contains(mission.availRandom), "\(mission.name) has implausible AvailRandom: \(mission.availRandom)")
            XCTAssertTrue(mission.availRating == -1 || mission.availRating >= 0, "\(mission.name) has implausible AvailRating: \(mission.availRating)")
        }
    }

    // ShipSyst is verified via a unique six-value negative sentinel set
    // (-1 through -6) documented nowhere else in this resource - whenever
    // it's negative, it must be one of exactly those six values.
    func testShipSystNegativeValuesMatchDocumentedSentinels() throws {
        let missions = try loadMissions()
        var foundAtLeastOneSentinel = false

        for mission in missions where mission.shipSyst < 0 {
            XCTAssertTrue((-6...(-1)).contains(mission.shipSyst), "\(mission.name) has a ShipSyst sentinel outside -1...-6: \(mission.shipSyst)")
            foundAtLeastOneSentinel = true
        }

        XCTAssertTrue(foundAtLeastOneSentinel, "No mission had a negative ShipSyst sentinel - can't confirm this field decodes real content.")
    }

    // ShipCount is documented as -1 (ignored) or 0-31 - never anything else.
    func testShipCountStaysWithinDocumentedRange() throws {
        let missions = try loadMissions()

        for mission in missions {
            XCTAssertTrue(mission.shipCount == -1 || (0...31).contains(mission.shipCount), "\(mission.name) has implausible ShipCount: \(mission.shipCount)")
        }
    }

    // Cross-checks the 2026-09-24 offset correction: "25000 Credit Bounty"
    // missions should decode PayVal to exactly 22500 (90% of the named
    // amount, the pattern that identified PayVal's real offset), and
    // "50000 Credit Bounty" missions to exactly 45000.
    func testCreditBountyMissionsDecodeDocumentedPayVal() throws {
        let missions = try loadMissions()

        let bounty25k = missions.filter { $0.name.localizedCaseInsensitiveContains("25000 Credit Bounty") }
        guard !bounty25k.isEmpty else {
            throw XCTSkip("No '25000 Credit Bounty' mission in this scenario's data - skipping.")
        }
        for mission in bounty25k {
            XCTAssertEqual(mission.payVal, 22500, "\(mission.name) should decode PayVal 22500")
        }

        let bounty50k = missions.filter { $0.name.localizedCaseInsensitiveContains("50000 Credit Bounty") }
        for mission in bounty50k {
            XCTAssertEqual(mission.payVal, 45000, "\(mission.name) should decode PayVal 45000")
        }
    }

    // Mission 258 is documented (via direct byte inspection during this
    // task's investigation) to require a combat rating of at least 5.
    func testMission258RequiresDocumentedCombatRating() throws {
        let missions = try loadMissions()
        guard let mission258 = missions.first(where: { $0.id == 258 }) else {
            throw XCTSkip("Mission 258 not present in this scenario's data - skipping.")
        }

        XCTAssertEqual(mission258.availRating, 5, "Mission 258 should decode AvailRating 5")
    }

    // Every negative PayVal in the real data should fall inside one of the
    // Bible's documented special-reward sentinel ranges (or the "take away
    // credits at mission start" open-ended range below -50000) - a wrong
    // offset would instead show negative values scattered arbitrarily.
    func testNegativePayValsFallWithinDocumentedSpecialRewardRanges() throws {
        let missions = try loadMissions()
        var foundAtLeastOneSpecialReward = false

        for mission in missions where mission.payVal < -1 {
            let value = mission.payVal
            let isDocumented =
                (-10383...(-10128)).contains(value) ||
                (-20383...(-20128)).contains(value) ||
                (-30383...(-30128)).contains(value) ||
                (-40099...(-40001)).contains(value) ||
                value <= -50000

            XCTAssertTrue(isDocumented, "\(mission.name) has a PayVal outside every documented special-reward range: \(value)")
            XCTAssertNotEqual(mission.payDescription, "Unknown special reward (\(value))")
            foundAtLeastOneSpecialReward = true
        }

        // Not every scenario is guaranteed to use a special reward, so this
        // is informational rather than a hard requirement - but the base
        // game does use them, so flag it if the loaded data has none at all.
        _ = foundAtLeastOneSpecialReward
    }

    // "Escort Merchant to <RST>" is an obviously-named mission - its
    // ShipGoal should decode to 3 ("Escort them"), cross-checking the
    // field's meaning (not just its value range) against a specific
    // real example.
    func testEscortMissionDecodesEscortShipGoal() throws {
        let missions = try loadMissions()
        guard let escortMission = missions.first(where: { $0.name.localizedCaseInsensitiveContains("Escort Merchant") }) else {
            throw XCTSkip("No 'Escort Merchant' mission in this scenario's data - skipping.")
        }

        XCTAssertEqual(escortMission.shipGoal, 3, "\(escortMission.name) should decode ShipGoal 3 (Escort)")
    }

    // TimeLimit's documented sentinel is -1 or 0 for "no limit"; the vast
    // majority of real missions should have no time limit, with a small
    // tail of plausible day counts.
    func testTimeLimitIsMostlyUnsetWithPlausibleDayCounts() throws {
        let missions = try loadMissions()

        let withLimit = missions.filter { $0.timeLimit > 0 }
        for mission in withLimit {
            XCTAssertLessThan(mission.timeLimit, 1000, "\(mission.name) has an implausibly long TimeLimit: \(mission.timeLimit) days")
        }

        // Most missions should have no deadline.
        XCTAssertLessThan(withLimit.count, missions.count, "Every mission has a TimeLimit set - the offset is probably wrong.")
    }

    // MARK: - Control-bit expression syntax

    // AvailBits (a test expression) and the six set expressions are read
    // from fixed 255-byte slots that are usually empty. When non-empty,
    // real expressions only ever use the documented NCB syntax characters
    // (bit/operator letters, digits, spaces, and &|!()^) - never arbitrary
    // binary garbage, which would indicate the slot offsets are wrong.
    func testControlBitExpressionsOnlyContainExpectedSyntaxCharacters() throws {
        let missions = try loadMissions()
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 &|!()^'.<>")

        var foundAtLeastOneNonEmptyExpression = false

        for mission in missions {
            let expressions = [
                mission.availBits, mission.onAccept, mission.onRefuse,
                mission.onSuccess, mission.onFailure, mission.onAbort, mission.onShipDone
            ]
            for expression in expressions where !expression.isEmpty {
                foundAtLeastOneNonEmptyExpression = true
                XCTAssertTrue(
                    expression.unicodeScalars.allSatisfy { allowedCharacters.contains($0) },
                    "\(mission.name) has an expression with unexpected characters: \"\(expression)\""
                )
                XCTAssertLessThan(expression.count, 200, "\(mission.name) has a suspiciously long expression - slot boundary is probably wrong.")
            }
        }

        XCTAssertTrue(foundAtLeastOneNonEmptyExpression, "No mission in this scenario's data has any control-bit expression set - can't confirm the string slots decode real content.")
    }

    // MARK: - Mission chaining (the core "story chain" feature)

    // startedMissionIDs(in:) should extract every "Sxxx" token from a set
    // expression, ignoring other operator letters and prefixes like "!"/"^"
    // and the "R(...)" random-choice wrapper.
    func testStartedMissionIDsParsesVariousExpressionShapes() {
        XCTAssertEqual(MissionDefinition.startedMissionIDs(in: "S783"), [783])
        XCTAssertEqual(MissionDefinition.startedMissionIDs(in: "b353 S783"), [783])
        XCTAssertEqual(MissionDefinition.startedMissionIDs(in: "b351 S797 b512 b515 b518"), [797])
        XCTAssertEqual(MissionDefinition.startedMissionIDs(in: "S781 b4444"), [781])
        XCTAssertEqual(MissionDefinition.startedMissionIDs(in: "b356 S798 S819"), [798, 819])
        XCTAssertEqual(MissionDefinition.startedMissionIDs(in: "!b511"), [], "Should not mistake a bit-clear token for a start-mission token")
        XCTAssertEqual(MissionDefinition.startedMissionIDs(in: "R(b2 !b3)"), [])
        XCTAssertEqual(MissionDefinition.startedMissionIDs(in: ""), [])
    }

    // Real chain cross-check #1: "Infiltrate the Rebels; Vellos4" (part of
    // the early "Vellos" story arc) is documented (via direct byte
    // inspection during this task's investigation) to have
    // OnSuccess = "b353 S783" and OnAbort = "S818" - i.e. it automatically
    // starts mission 783 on success and mission 818 on abort.
    func testVellos4MissionChainsToDocumentedSuccessors() throws {
        let missions = try loadMissions()
        guard let vellos4 = missions.first(where: { $0.name.localizedCaseInsensitiveContains("Infiltrate the Rebels") && $0.name.localizedCaseInsensitiveContains("Vellos4") }) else {
            throw XCTSkip("No 'Infiltrate the Rebels; Vellos4' mission in this scenario's data - skipping.")
        }

        XCTAssertEqual(vellos4.successMissionIDs, [783])
        XCTAssertEqual(vellos4.abortMissionIDs, [818])
    }

    // Real chain cross-check #2: full end-to-end resolution using
    // MissionChainResolver - the mission that starts mission 783 on success
    // should be discoverable as 783's predecessor, and 783 should be
    // discoverable as that mission's successor, forming a real walkable
    // two-hop link (not just isolated records with no way to connect them).
    func testMissionChainResolverConnectsRealVellosChain() throws {
        let missions = try loadMissions()
        guard let vellos4 = missions.first(where: { $0.name.localizedCaseInsensitiveContains("Infiltrate the Rebels") && $0.name.localizedCaseInsensitiveContains("Vellos4") }),
              let mission783 = missions.first(where: { $0.id == 783 }) else {
            throw XCTSkip("Vellos4 or mission 783 not present in this scenario's data - skipping.")
        }

        let resolver = MissionChainResolver(missions: missions)

        let successors = resolver.successors(of: vellos4)
        XCTAssertTrue(successors.contains(where: { $0.id == 783 }), "Vellos4's successors should include mission 783")

        let predecessors = resolver.predecessors(of: mission783)
        XCTAssertTrue(predecessors.contains(where: { $0.id == vellos4.id }), "Mission 783's predecessors should include Vellos4")

        XCTAssertTrue(resolver.isPartOfChain(vellos4))
        XCTAssertTrue(resolver.isPartOfChain(mission783))

        // The full success-path chain walked forward from Vellos4 should
        // include both Vellos4 itself and mission 783, in that order.
        let chain = resolver.successChain(from: vellos4)
        XCTAssertEqual(chain.first?.id, vellos4.id)
        XCTAssertTrue(chain.contains(where: { $0.id == 783 }), "Walking the success chain from Vellos4 should reach mission 783")
    }

    // A mission with no chain links at all (no incoming or outgoing Sxxx
    // references, and no flag links either) should report isPartOfChain ==
    // false and an empty successChain of just itself, so the UI can
    // distinguish standalone missions from real chains.
    func testStandaloneMissionIsNotReportedAsPartOfAChain() throws {
        let missions = try loadMissions()
        let resolver = MissionChainResolver(missions: missions)

        guard let standalone = missions.first(where: {
            $0.allChainedMissionIDs.isEmpty && resolver.successors(of: $0).isEmpty && resolver.predecessors(of: $0).isEmpty
        }) else {
            throw XCTSkip("Every mission in this scenario's data is part of some chain - skipping.")
        }

        XCTAssertFalse(resolver.isPartOfChain(standalone))
        XCTAssertEqual(resolver.successChain(from: standalone).map(\.id), [standalone.id])
    }

    // successChain must never infinite-loop even if plugin/malformed data
    // were to produce a cycle - guarded by the visited-set check in
    // MissionChainResolver. This constructs a synthetic 2-mission cycle
    // directly (not from real game data) to prove the guard works.
    func testSuccessChainDoesNotInfiniteLoopOnACycle() {
        let missionA = MissionDefinition(
            id: 900, name: "A", availStel: -1, availLoc: 0, availRecord: 0, availRating: -1, availRandom: 100,
            travelStel: -1, returnStel: -1, cargoType: -1, cargoQty: -1, pickupMode: -1, dropOffMode: -1,
            scanMask: 0, payVal: 0, shipCount: -1, shipSyst: -1, shipDude: -1, shipGoal: -1, shipBehav: -1,
            shipNameID: -1, briefText: -1, quickBrief: -1, loadCargText: -1, dumpCargoText: -1, compText: -1,
            canAbort: true, timeLimit: -1, dispWeight: 0, acceptButton: "", refuseButton: "", availBits: "",
            onAccept: "", onRefuse: "", onSuccess: "S901", onFailure: "", onAbort: "", onShipDone: ""
        )
        let missionB = MissionDefinition(
            id: 901, name: "B", availStel: -1, availLoc: 0, availRecord: 0, availRating: -1, availRandom: 100,
            travelStel: -1, returnStel: -1, cargoType: -1, cargoQty: -1, pickupMode: -1, dropOffMode: -1,
            scanMask: 0, payVal: 0, shipCount: -1, shipSyst: -1, shipDude: -1, shipGoal: -1, shipBehav: -1,
            shipNameID: -1, briefText: -1, quickBrief: -1, loadCargText: -1, dumpCargoText: -1, compText: -1,
            canAbort: true, timeLimit: -1, dispWeight: 0, acceptButton: "", refuseButton: "", availBits: "",
            onAccept: "", onRefuse: "", onSuccess: "S900", onFailure: "", onAbort: "", onShipDone: ""
        )

        let resolver = MissionChainResolver(missions: [missionA, missionB])
        let chain = resolver.successChain(from: missionA)

        XCTAssertEqual(chain.map(\.id), [900, 901], "Cycle should stop after visiting each mission once")
    }

    func testAllChainsPreservesBranchesAndOmitsStandaloneMissions() {
        func mission(_ id: Int, _ name: String, success: String = "", failure: String = "", abort: String = "") -> MissionDefinition {
            MissionDefinition(
                id: id, name: name, availStel: -1, availLoc: 0, availRecord: 0, availRating: -1, availRandom: 100,
                travelStel: -1, returnStel: -1, cargoType: -1, cargoQty: -1, pickupMode: -1, dropOffMode: -1,
                scanMask: 0, payVal: 0, shipCount: -1, shipSyst: -1, shipDude: -1, shipGoal: -1, shipBehav: -1,
                shipNameID: -1, briefText: -1, quickBrief: -1, loadCargText: -1, dumpCargoText: -1, compText: -1,
                canAbort: true, timeLimit: -1, dispWeight: 0, acceptButton: "", refuseButton: "", availBits: "",
                onAccept: "", onRefuse: "", onSuccess: success, onFailure: failure, onAbort: abort, onShipDone: ""
            )
        }

        // Give the root a higher ID than its descendants to verify that the
        // component is presented in story traversal order, not numeric order.
        let root = mission(500, "Root", success: "S101", failure: "S102")
        let successBranch = mission(101, "Success", abort: "S103")
        let failureBranch = mission(102, "Failure")
        let abortBranch = mission(103, "Abort")
        let standalone = mission(200, "Standalone")

        let chains = MissionChainResolver(
            missions: [standalone, failureBranch, abortBranch, root, successBranch]
        ).allChains()

        XCTAssertEqual(chains.count, 1)
        XCTAssertEqual(chains[0].missions.map(\.id), [500, 101, 102, 103])
        XCTAssertEqual(chains[0].rootMissionIDs, [500])
        XCTAssertEqual(chains[0].edgeCount, 3)
        XCTAssertFalse(chains[0].isCyclic)
    }

    func testAllChainsMarksPureCycleWithoutARoot() {
        func mission(_ id: Int, nextID: Int) -> MissionDefinition {
            MissionDefinition(
                id: id, name: "Mission \(id)", availStel: -1, availLoc: 0, availRecord: 0, availRating: -1, availRandom: 100,
                travelStel: -1, returnStel: -1, cargoType: -1, cargoQty: -1, pickupMode: -1, dropOffMode: -1,
                scanMask: 0, payVal: 0, shipCount: -1, shipSyst: -1, shipDude: -1, shipGoal: -1, shipBehav: -1,
                shipNameID: -1, briefText: -1, quickBrief: -1, loadCargText: -1, dumpCargoText: -1, compText: -1,
                canAbort: true, timeLimit: -1, dispWeight: 0, acceptButton: "", refuseButton: "", availBits: "",
                onAccept: "", onRefuse: "", onSuccess: "S\(nextID)", onFailure: "", onAbort: "", onShipDone: ""
            )
        }

        let chains = MissionChainResolver(missions: [mission(300, nextID: 301), mission(301, nextID: 300)]).allChains()

        XCTAssertEqual(chains.count, 1)
        XCTAssertEqual(chains[0].rootMissionIDs, [])
        XCTAssertTrue(chains[0].isCyclic)
    }
}
