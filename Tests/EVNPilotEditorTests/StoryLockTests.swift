import XCTest
@testable import EVNPilotEditor

// Regression tests for the Geuis/Polaris case: a main storyline that
// can't start because another storyline holds the shared "storyline in
// progress" flags (511/515). Covers requirement polarity through negated
// groups, the "Done" heuristic, lock explanations, and flag-linked chains.
final class StoryLockTests: XCTestCase {
    // MARK: - Builders

    private func mission(
        id: Int,
        name: String,
        availBits: String = "",
        onAccept: String = "",
        onSuccess: String = "",
        onAbort: String = "",
        onFailure: String = "",
        canAbort: Bool = true,
        timeLimit: Int16 = -1
    ) -> MissionDefinition {
        MissionDefinition(
            id: id, name: name, availStel: -1, availLoc: 0, availRecord: 0,
            availRating: -1, availRandom: 100,
            travelStel: -1, returnStel: -1, cargoType: -1, cargoQty: -1, pickupMode: -1, dropOffMode: -1,
            scanMask: 0, payVal: 0, shipCount: -1, shipSyst: -1, shipDude: -1, shipGoal: -1, shipBehav: -1,
            shipNameID: -1, briefText: -1, quickBrief: -1, loadCargText: -1, dumpCargoText: -1, compText: -1,
            canAbort: canAbort, timeLimit: timeLimit, dispWeight: 0, acceptButton: "", refuseButton: "",
            availBits: availBits, onAccept: onAccept, onRefuse: "", onSuccess: onSuccess,
            onFailure: onFailure, onAbort: onAbort, onShipDone: ""
        )
    }

    private func state(flagsOn: [Int]) -> PilotStoryState {
        var bits: [Bool] = [Bool](repeating: false, count: 1000)

        for flagID in flagsOn {
            bits[flagID] = true
        }

        return PilotStoryState(
            bits: bits,
            outfitCounts: [Int16](repeating: 0, count: 100),
            exploration: [Int16](repeating: 0, count: 100),
            combatRating: 0,
            isMale: true,
            activeMissionIDs: []
        )
    }

    // A small version of the real data: Wild Geese 1 turns on the shared
    // flags 511/515, three other storyline starters do too (which is what
    // makes them shared), Wild Geese 5b releases them when aborted, and
    // Polaris 1 needs them off.
    private func storylineMissions() -> [MissionDefinition] {
        [
            mission(id: 634, name: "Take Michaleen to New Ireland;Wild Geese 1", availBits: "!b800 & !(b511 | b515)", onAccept: "b511", onSuccess: "b800 b515"),
            mission(id: 644, name: "Deliver Explosives to Ryll;Wild Geese 5b", availBits: "b800 & !b815", onSuccess: "b815", onAbort: "!b511 !b515"),
            mission(id: 150, name: "Transport Mu'Randa;Polaris1", availBits: "!(b275 | b512) & !(b511 | b515)", onAccept: "b511", onSuccess: "b275 b515"),
            mission(id: 700, name: "Starter A;Fed1", onAccept: "b511", onSuccess: "b515"),
            mission(id: 701, name: "Starter B;Rebel1", onAccept: "b511", onSuccess: "b515"),
            mission(id: 702, name: "Starter C;Auroran1", onAccept: "b511", onSuccess: "b515")
        ]
    }

    private func diagnostics(flagsOn: [Int]) -> MissionDiagnostics {
        let missions: [MissionDefinition] = storylineMissions()
        let storyFlags: [Int: StoryFlagMetadata] = StoryFlagCatalog(missions: missions, outfits: [], ships: []).flagsByID
        return MissionDiagnostics(missions: missions, storyFlags: storyFlags, state: state(flagsOn: flagsOn))
    }

    // MARK: - Requirement polarity

    func testNegatedGroupRequiresEveryFlagInsideToBeOff() {
        let operations = StoryFlagCatalog.bitOperations(in: "!(b275 | b512) & !((b511 | b515) | b6666)", isTest: true)

        XCTAssertEqual(operations.map(\.id), [275, 512, 511, 515, 6666])
        XCTAssertTrue(operations.allSatisfy { $0.effect == .requiresClear })
    }

    func testMixedRequirementKeepsPolarityPerFlag() {
        let operations = StoryFlagCatalog.bitOperations(in: "(b278 & !b315) & !(b279 | b316)", isTest: true)
        let effects: [Int: StoryFlagEffect] = Dictionary(uniqueKeysWithValues: operations.map { ($0.id, $0.effect) })

        XCTAssertEqual(effects[278], .requiresSet)
        XCTAssertEqual(effects[315], .requiresClear)
        XCTAssertEqual(effects[279], .requiresClear)
        XCTAssertEqual(effects[316], .requiresClear)
    }

    // MARK: - "Done" heuristic and lock explanation

    func testSharedLockFlagDoesNotMakeMissionLookDone() {
        // Geuis: finished Wild Geese 1, never did Polaris 1.
        let result = diagnostics(flagsOn: [511, 515, 800])

        XCTAssertEqual(result.diagnosis(for: 150)?.status, .blocked)
        XCTAssertEqual(result.diagnosis(for: 634)?.status, .completed)
        XCTAssertEqual(result.diagnosis(for: 644)?.status, .available)
    }

    func testLockIssueNamesTheMissionThatHoldsTheFlagAndHowToRelease() throws {
        let result = diagnostics(flagsOn: [511, 515, 800])
        let issues: [MissionIssue] = try XCTUnwrap(result.diagnosis(for: 150)?.issues)
        let lock: MissionIssue = try XCTUnwrap(issues.first { $0.id == "lock-511-515" })

        // One entry for both flags, since the same mission holds both.
        XCTAssertEqual(issues.filter { $0.id.hasPrefix("lock-") }.count, 1)
        XCTAssertEqual(lock.relatedFlagIDs, [511, 515])
        XCTAssertEqual(lock.severity, .blocker)
        // 511 and 515 are shared storyline locks, so the storyline is named.
        XCTAssertEqual(lock.title, "A main storyline is still in progress (most likely Wild Geese)")
        XCTAssertTrue(lock.detail.hasPrefix("Only one main storyline can run at a time."), lock.detail)
        XCTAssertTrue(lock.detail.contains("you did 'Take Michaleen to New Ireland (Wild Geese 1)'"), lock.detail)
        XCTAssertTrue(lock.detail.contains("abort 'Deliver Explosives to Ryll (Wild Geese 5b)'"), lock.detail)
        XCTAssertEqual(lock.fix, .missionOutcome(missionID: 644, event: "aborted"))
        XCTAssertEqual(lock.relatedMissionIDs, [634, 644])

        // The long generic list is replaced, not repeated.
        XCTAssertFalse(issues.contains { $0.id == "bit-511-requiresClear" || $0.id == "bit-515-requiresClear" })
        XCTAssertFalse(issues.contains { $0.id.hasPrefix("conflict-511-") || $0.id.hasPrefix("conflict-515-") })
    }

    // MARK: - Ways out the player controls

    // The Geuis case: Wild Geese 1 left 511 on, and the only mission that
    // clears it is the pirate cargo pickup, and only when that fails.
    private func lockDetail(releaser: MissionDefinition, flagsOn: [Int] = [511, 800, 810], extra: [MissionDefinition] = []) throws -> MissionIssue {
        let missions: [MissionDefinition] = [
            mission(id: 634, name: "Take Michaleen to New Ireland;Wild Geese 1", availBits: "!b800", onAccept: "b511", onSuccess: "b800"),
            mission(id: 150, name: "Transport Mu'Randa;Polaris1", availBits: "!b275 & !b511", onSuccess: "b275"),
            releaser
        ] + extra
        let storyFlags: [Int: StoryFlagMetadata] = StoryFlagCatalog(missions: missions, outfits: [], ships: []).flagsByID
        let result = MissionDiagnostics(missions: missions, storyFlags: storyFlags, state: state(flagsOn: flagsOn))

        return try XCTUnwrap(result.diagnosis(for: 150)?.issues.first { $0.id.hasPrefix("lock-") })
    }

    func testFailingIsNotSuggestedWhenTheMissionCantFail() throws {
        let pickup = mission(id: 810, name: "Pick Up Cargo From Sol;Pirate 001", availBits: "b810", onSuccess: "b600", onFailure: "b600 !b511")
        let lock: MissionIssue = try lockDetail(releaser: pickup)

        XCTAssertFalse(lock.detail.contains("fail 'Pick Up Cargo"), lock.detail)
        XCTAssertTrue(lock.detail.contains("Nothing you can do in the game turns story flag 511 off any more"), lock.detail)
        XCTAssertFalse(lock.relatedMissionIDs.contains(810))
    }

    func testFailingIsSuggestedWithTheReasonWhenTheMissionIsTimed() throws {
        let pickup = mission(id: 810, name: "Pick Up Cargo From Sol;Pirate 001", availBits: "b810", onSuccess: "b600", onFailure: "b600 !b511", timeLimit: 20)
        let lock: MissionIssue = try lockDetail(releaser: pickup)

        XCTAssertTrue(lock.detail.contains("fail 'Pick Up Cargo From Sol (Pirate 001)' (only if it fails, by running out of time)"), lock.detail)
        XCTAssertTrue(lock.detail.contains("(aborting it won't help)"), lock.detail)
    }

    func testAbortIsNotSuggestedWhenTheMissionCantBeAborted() throws {
        let pickup = mission(id: 810, name: "Pick Up Cargo From Sol;Pirate 001", availBits: "b810", onAbort: "!b511", canAbort: false)
        let lock: MissionIssue = try lockDetail(releaser: pickup)

        XCTAssertFalse(lock.detail.contains("abort"), lock.detail)
        XCTAssertTrue(lock.detail.contains("Nothing you can do in the game"), lock.detail)
    }

    func testCompletingIsSuggestedWithoutAnAbortWarningWhenAbortingAlsoWorks() throws {
        let pickup = mission(id: 810, name: "Pick Up Cargo From Sol;Pirate 001", availBits: "b810", onSuccess: "!b511", onAbort: "!b511")
        let lock: MissionIssue = try lockDetail(releaser: pickup)

        XCTAssertTrue(lock.detail.contains("abort or complete 'Pick Up Cargo From Sol (Pirate 001)'"), lock.detail)
        XCTAssertFalse(lock.detail.contains("won't help"), lock.detail)
    }

    func testBlockedReleaserIsNamedAsALaterWayOut() throws {
        // 810 is off, so the ending isn't offered yet; the mission before
        // it that turns 810 on hasn't been done.
        let ending = mission(id: 649, name: "Final Report;Wild Geese 9", availBits: "b810", onSuccess: "!b511")
        let before = mission(id: 648, name: "Hand-off;Wild Geese 8", availBits: "b800 & !b810", onSuccess: "b810")
        let lock: MissionIssue = try lockDetail(releaser: ending, flagsOn: [511, 800], extra: [before])

        XCTAssertTrue(lock.detail.contains("but 'Final Report (Wild Geese 9)' could later, once it's offered"), lock.detail)
        XCTAssertTrue(lock.relatedMissionIDs.contains(649))
    }

    func testBranchTheStoryWentPastIsNotNamedAsALaterWayOut() throws {
        // Wild Geese 2 already picked 805 over 804, so 3a can't come up.
        let branchA = mission(id: 636, name: "Return Michaleen's body;Wild Geese 3a", availBits: "b804", onSuccess: "!b511")
        let wildGeese2 = mission(id: 635, name: "Take Michaleen to Sol;Wild Geese 2", availBits: "b800 & !b802", onSuccess: "b802 R(b804 b805)")
        let lock: MissionIssue = try lockDetail(releaser: branchA, flagsOn: [511, 800, 802, 805], extra: [wildGeese2])

        XCTAssertFalse(lock.detail.contains("could later"), lock.detail)
        XCTAssertTrue(lock.detail.contains("Nothing you can do in the game"), lock.detail)
    }

    func testOtherStorylinesAreNotNamedAsALaterWayOut() throws {
        // Vell-os clears 511 partway through, but can't start while it's on.
        let vellos = mission(id: 129, name: "Visit Vell-os Homeworld;Vellos2", availBits: "b810", onSuccess: "!b511")
        let before = mission(id: 648, name: "Hand-off;Wild Geese 8", availBits: "b800 & !b810", onSuccess: "b810")
        let lock: MissionIssue = try lockDetail(releaser: vellos, flagsOn: [511, 800], extra: [before])

        XCTAssertFalse(lock.detail.contains("could later"), lock.detail)
        XCTAssertTrue(lock.detail.contains("Nothing you can do in the game"), lock.detail)
    }

    // MARK: - Editor fixes

    func testFixCopiesTheOutcomeThatClearsTheLockEvenIfThePlayerCantCauseIt() throws {
        // The Geuis case: failing the pickup is the story's own way to clear
        // 511, even though this mission can't actually fail.
        let pickup = mission(id: 810, name: "Pick Up Cargo From Sol;Pirate 001", availBits: "b810", onSuccess: "b600", onFailure: "b600 !b511")
        let lock: MissionIssue = try lockDetail(releaser: pickup)

        XCTAssertEqual(lock.fix, .missionOutcome(missionID: 810, event: "failed"))
    }

    func testFixPrefersAnOutcomeThatClearsEveryLockFlag() throws {
        let partial = mission(id: 700, name: "Partial;Other1", availBits: "b810", onSuccess: "!b511")
        let full = mission(id: 701, name: "Full;Other2", availBits: "b810", onAbort: "!b511 !b515")
        let missions: [MissionDefinition] = [
            mission(id: 634, name: "Take Michaleen to New Ireland;Wild Geese 1", availBits: "!b800", onAccept: "b511 b515", onSuccess: "b800"),
            mission(id: 150, name: "Transport Mu'Randa;Polaris1", availBits: "!b275 & !(b511 | b515)", onSuccess: "b275"),
            partial,
            full
        ]
        let storyFlags: [Int: StoryFlagMetadata] = StoryFlagCatalog(missions: missions, outfits: [], ships: []).flagsByID
        let result = MissionDiagnostics(missions: missions, storyFlags: storyFlags, state: state(flagsOn: [511, 515, 800, 810]))
        let lock: MissionIssue = try XCTUnwrap(result.diagnosis(for: 150)?.issues.first { $0.id.hasPrefix("lock-") })

        XCTAssertEqual(lock.fix, .missionOutcome(missionID: 701, event: "aborted"))
    }

    func testFixFallsBackToClearingTheFlags() throws {
        // Nothing in the data clears 511 except this mission's success,
        // and it's the locked mission itself.
        let unrelated = mission(id: 810, name: "Pick Up Cargo From Sol;Pirate 001", availBits: "b810", onSuccess: "b600")
        let lock: MissionIssue = try lockDetail(releaser: unrelated)

        XCTAssertEqual(lock.fix, .clearFlags([511]))
    }

    func testCopiedOutcomeChangesMatchTheGame() {
        // What the fix applies for the Geuis case, from flags as they were.
        let steps = MissionCompletion.parse("b600 !b511")
        let current: [Bool] = state(flagsOn: [511, 810]).bits

        XCTAssertEqual(MissionCompletion.changes(for: steps, currentBits: current, choices: []), [600: true, 511: false])
    }

    func testStorylineTagComesFromTheMissionNote() {
        XCTAssertEqual(MissionStoryline.tag(of: mission(id: 1, name: "Take Michaleen;Wild Geese 1")), "Wild Geese")
        XCTAssertEqual(MissionStoryline.tag(ofNote: "Rebel II14 - Unregistered cutoff"), "Rebel II")
        XCTAssertNil(MissionStoryline.tag(of: mission(id: 1, name: "No tag")))
    }

    func testMissionIsDoneWhenItsOwnSuccessFlagIsOn() {
        // Pilot who really finished Polaris 1: its specific flag 275 is on.
        let result = diagnostics(flagsOn: [275, 511, 515])

        XCTAssertEqual(result.diagnosis(for: 150)?.status, .completed)
    }

    func testIssueIDsAreUniqueWhenOneMissionSetsTheFlagTwice() throws {
        // Mission 150 turns 511 on at accept and 515 at success, and the
        // starters set both; without de-duplication the IDs would repeat.
        let result = diagnostics(flagsOn: [511, 515])
        let issues: [MissionIssue] = try XCTUnwrap(result.diagnosis(for: 634)?.issues)

        XCTAssertEqual(Set(issues.map(\.id)).count, issues.count)
    }

    func testSharedFlagIsNamedAsShared() throws {
        let missions: [MissionDefinition] = storylineMissions()
        let storyFlags: [Int: StoryFlagMetadata] = StoryFlagCatalog(missions: missions, outfits: [], ships: []).flagsByID

        // 511 is turned on by five missions here.
        let name: String = try XCTUnwrap(storyFlags[511]?.name)
        XCTAssertTrue(name.hasPrefix("Shared story flag, turned on by 5 missions"), name)

        // 800 is only Wild Geese 1's, so it keeps a specific name.
        XCTAssertEqual(storyFlags[800]?.name, "Take Michaleen to New Ireland (Completed)")
    }

    // MARK: - Flag-linked chains

    func testSuccessFlagLinksToTheMissionWaitingForIt() {
        let first = mission(id: 900, name: "First;Polaris1", onSuccess: "b275")
        let second = mission(id: 901, name: "Second;Polaris2", availBits: "b275 & !b276")
        let resolver = MissionChainResolver(missions: [first, second])

        XCTAssertEqual(resolver.successors(of: first).map(\.id), [901])
        XCTAssertEqual(resolver.predecessors(of: second).map(\.id), [900])
        XCTAssertEqual(resolver.unlockFlag(from: first, to: 901), 275)
        XCTAssertEqual(resolver.allChains().first?.missions.map(\.id), [900, 901])
    }

    func testSharedFlagDoesNotLinkMissions() {
        let setters: [MissionDefinition] = (0..<4).map { index in
            mission(id: 910 + index, name: "Setter \(index)", onSuccess: "b518")
        }
        let waiter = mission(id: 920, name: "Waiter", availBits: "b518")
        let resolver = MissionChainResolver(missions: setters + [waiter])

        XCTAssertTrue(resolver.predecessors(of: waiter).isEmpty)
        XCTAssertTrue(resolver.allChains().isEmpty)
    }

    func testLinkedStorylinesStayInSeparateChains() {
        let wildGeese = mission(id: 930, name: "Talk with Rebels;Wild Geese 7a", onSuccess: "b810")
        let pirate = mission(id: 931, name: "Pick Up Cargo;Pirate 001", availBits: "b810", onSuccess: "b811")
        let pirateNext = mission(id: 932, name: "Take Cargo;Pirate 002", availBits: "b811")
        let resolver = MissionChainResolver(missions: [wildGeese, pirate, pirateNext])
        let chains: [[Int]] = resolver.allChains().map { $0.missions.map(\.id) }

        // Still linked for "leads to"...
        XCTAssertEqual(resolver.successors(of: wildGeese).map(\.id), [931])

        // ...but grouped by storyline.
        XCTAssertTrue(chains.contains([931, 932]), "\(chains)")
        XCTAssertFalse(chains.contains { $0.contains(930) && $0.contains(931) }, "\(chains)")
    }

    func testStorylineFamilyIgnoresNumbersAndSpelling() {
        let family: (String) -> String? = { name in
            MissionChainResolver.storylineFamily(of: self.mission(id: 1, name: name))
        }

        XCTAssertEqual(family("Pick up Bis Andreya;Polaris4 CONTINUE"), "polaris")
        XCTAssertEqual(family("ATTN: <PN>;Polaris ActionMan 001"), "polaris")
        XCTAssertEqual(family("Visit;Vell-os 3"), family("Visit; Vellos2"))
        XCTAssertEqual(family("Report;Rebel II14"), family("Report;Rebel I11"))
        XCTAssertNil(family("No tag here"))
    }

    // MARK: - Real data

    func testRealPolarisStorylineIsOneChainAndNothingIsGiant() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/EV Nova/Nova Files", isDirectory: true)

        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("EV Nova game files not found - skipping real-data check.")
        }

        let missions = MissionDefinition.decodeAll(from: try GameDataLibrary(contentsOfDirectory: directory))
        let chains = MissionChainResolver(missions: missions).allChains()
        let polaris = try XCTUnwrap(chains.first { chain in chain.missions.contains { $0.id == 150 } })

        // Polaris 1 through the last Polaris mission (192, "Head to Port Kane").
        XCTAssertTrue(polaris.missions.contains { $0.id == 192 })

        // Guards against shared flags merging every storyline together.
        XCTAssertLessThan(chains.map(\.missions.count).max() ?? 0, 150)
    }
}
