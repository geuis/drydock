import XCTest
@testable import EVNPilotEditor

final class MissionCompletionTests: XCTestCase {
    private func mission(id: Int, name: String, availBits: String = "", onAccept: String = "", onSuccess: String = "") -> MissionDefinition {
        MissionDefinition(
            id: id, name: name, availStel: -1, availLoc: 0, availRecord: 0,
            availRating: -1, availRandom: 100,
            travelStel: -1, returnStel: -1, cargoType: -1, cargoQty: -1, pickupMode: -1, dropOffMode: -1,
            scanMask: 0, payVal: 0, shipCount: -1, shipSyst: -1, shipDude: -1, shipGoal: -1, shipBehav: -1,
            shipNameID: -1, briefText: -1, quickBrief: -1, loadCargText: -1, dumpCargoText: -1, compText: -1,
            canAbort: true, timeLimit: -1, dispWeight: 0, acceptButton: "", refuseButton: "",
            availBits: availBits, onAccept: onAccept, onRefuse: "", onSuccess: onSuccess,
            onFailure: "", onAbort: "", onShipDone: ""
        )
    }

    private func bits(on flagIDs: [Int]) -> [Bool] {
        var result: [Bool] = [Bool](repeating: false, count: 1000)

        for flagID in flagIDs {
            result[flagID] = true
        }

        return result
    }

    func testParsesFlagsRandomChoicesAndOtherEffects() {
        let steps = NCBSetExpression.parse("b800 R(b804 b805) S733 !b12 ^b3")

        XCTAssertEqual(steps, [
            .single(.set(800)),
            .randomChoice([.set(804), .set(805)]),
            .single(.other("S733")),
            .single(.clear(12)),
            .single(.toggle(3))
        ])
    }

    func testDoneAppliesAcceptThenSuccess() {
        let polaris1 = mission(id: 150, name: "Transport Mu'Randa;Polaris1", onAccept: "b511", onSuccess: "b275 b515")
        let changes = MissionCompletion(mission: polaris1).doneChanges(currentBits: bits(on: []), choices: [])

        XCTAssertEqual(changes, [511: true, 275: true, 515: true])
    }

    func testDoneOnlyReportsRealChanges() {
        let polaris1 = mission(id: 150, name: "Transport Mu'Randa;Polaris1", onAccept: "b511", onSuccess: "b275 b515")
        let changes = MissionCompletion(mission: polaris1).doneChanges(currentBits: bits(on: [511]), choices: [])

        XCTAssertEqual(changes, [275: true, 515: true])
    }

    func testRandomChoiceTakesThePickedTrack() {
        let wildGeese2 = mission(id: 635, name: "Take Michaleen to Sol;Wild Geese 2", onSuccess: "b802 R(b804 b805)")
        let completion = MissionCompletion(mission: wildGeese2)

        XCTAssertEqual(completion.randomChoices, [[.set(804), .set(805)]])
        XCTAssertEqual(completion.doneChanges(currentBits: bits(on: []), choices: [1]), [802: true, 805: true])
    }

    func testNotDoneLeavesSharedFlagsAlone() {
        let polaris1 = mission(id: 150, name: "Transport Mu'Randa;Polaris1", onAccept: "b511", onSuccess: "b275 b515")
        let completion = MissionCompletion(mission: polaris1)
        let current = bits(on: [511, 275, 515])
        let isShared: (Int) -> Bool = { $0 == 511 || $0 == 515 }

        XCTAssertEqual(completion.notDoneChanges(currentBits: current, isShared: isShared), [275: false])
        XCTAssertEqual(completion.sharedFlagsLeftOn(currentBits: current, isShared: isShared), [511, 515])
    }

    func testMissionThatTurnsItsOwnFlagBackOffIsRepeatable() {
        let reportMuhari = mission(id: 362, name: "Report Mu'hari; Vellos24", availBits: "b371 & !b417", onAccept: "b417", onSuccess: "!b417")
        let polaris1 = mission(id: 150, name: "Transport Mu'Randa;Polaris1", onAccept: "b511", onSuccess: "b275 b515")

        XCTAssertTrue(MissionCompletion(mission: reportMuhari).isRepeatable)
        XCTAssertFalse(MissionCompletion(mission: polaris1).isRepeatable)
    }

    func testOtherEffectsAreReported() {
        let wildGeese5b = mission(id: 644, name: "Deliver Explosives to Ryll;Wild Geese 5b", onAccept: "S733", onSuccess: "b815 b6666")

        XCTAssertEqual(MissionCompletion(mission: wildGeese5b).otherEffects, ["S733"])
    }

    // End to end: after applying the changes, the diagnosis agrees the
    // mission is done and the next one opens up.
    func testMarkingDoneMakesDiagnosisShowCompleted() {
        let first = mission(id: 900, name: "First;Test1", availBits: "!b700", onSuccess: "b700")
        let second = mission(id: 901, name: "Second;Test2", availBits: "b700 & !b701", onSuccess: "b701")
        let missions = [first, second]
        var current = bits(on: [])

        for (flagID, value) in MissionCompletion(mission: first).doneChanges(currentBits: current, choices: []) {
            current[flagID] = value
        }

        let storyFlags = StoryFlagCatalog(missions: missions, outfits: [], ships: []).flagsByID
        let state = PilotStoryState(bits: current, outfitCounts: [Int16](repeating: 0, count: 100), exploration: [Int16](repeating: 0, count: 100), combatRating: 0, isMale: true, activeMissionIDs: [])
        let diagnostics = MissionDiagnostics(missions: missions, storyFlags: storyFlags, state: state)

        XCTAssertEqual(diagnostics.diagnosis(for: 900)?.status, .completed)
        XCTAssertEqual(diagnostics.diagnosis(for: 901)?.status, .available)
    }
}
