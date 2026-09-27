import Foundation

// Marks a mission done or not done by changing story flags, since the pilot
// file has no "completed" record of its own: the game remembers finished
// missions only through the flags their outcomes set, and those same flags
// are what unlock the next missions.
//
// Done applies the mission's accept and success flag changes in the order
// the game would. Not done turns off the flags it turns on, except shared
// "storyline in progress" markers that other missions rely on too. Other
// effects (starting missions, giving items, moving the player) can't be
// expressed as flags and are only reported.
struct MissionCompletion {
    // The parser lives in NCBSetExpression; these names keep this type's
    // signatures readable.
    typealias Operation = NCBSetExpression.Operation
    typealias Step = NCBSetExpression.Step

    let steps: [Step]

    init(mission: MissionDefinition) {
        // Accepting comes before succeeding, so success wins any overlap.
        steps = NCBSetExpression.parse(mission.onAccept) + NCBSetExpression.parse(mission.onSuccess)
    }

    // The random choices, in order, for the player to pick from.
    var randomChoices: [[Operation]] {
        steps.compactMap { step in
            if case .randomChoice(let options) = step { return options }
            return nil
        }
    }

    // Effects that aren't flag changes, as written in the game data.
    var otherEffects: [String] {
        Self.otherEffects(in: steps)
    }

    // New values for the flags marking the mission done would change.
    // `choices` picks an option per random choice, in order; missing
    // entries take the first option.
    func doneChanges(currentBits: [Bool], choices: [Int]) -> [Int: Bool] {
        Self.changes(for: steps, currentBits: currentBits, choices: choices)
    }

    // New values for the flags applying `steps` would change, in order.
    // Also used by the story-lock fix, which copies another outcome.
    static func changes(for steps: [Step], currentBits: [Bool], choices: [Int]) -> [Int: Bool] {
        var values: [Int: Bool] = [:]
        var choiceIndex: Int = 0

        let current: (Int) -> Bool = { flagID in
            values[flagID] ?? (currentBits.indices.contains(flagID) && currentBits[flagID])
        }

        for step in steps {
            let operation: Operation

            switch step {
            case .single(let single):
                operation = single

            case .randomChoice(let options):
                let picked: Int = choiceIndex < choices.count ? choices[choiceIndex] : 0
                choiceIndex += 1
                guard options.indices.contains(picked) else { continue }
                operation = options[picked]
            }

            switch operation {
            case .set(let id): values[id] = true
            case .clear(let id): values[id] = false
            case .toggle(let id): values[id] = !current(id)
            case .other: break
            }
        }

        // Only what actually differs from the pilot's flags now.
        return values.filter { flagID, value in
            let original: Bool = currentBits.indices.contains(flagID) && currentBits[flagID]
            return original != value
        }
    }

    // Effects in `steps` that aren't flag changes, as written.
    static func otherEffects(in steps: [Step]) -> [String] {
        steps.flatMap(\.operations)
        .compactMap { operation in
            if case .other(let text) = operation { return text }
            return nil
        }
    }

    // The set expression a mission runs for one outcome, named as the
    // story-flag references name it.
    static func expression(for event: String, of mission: MissionDefinition) -> String {
        switch event {
        case "accepted": return mission.onAccept
        case "refused": return mission.onRefuse
        case "completed": return mission.onSuccess
        case "failed": return mission.onFailure
        case "aborted": return mission.onAbort
        case "ship objective completed": return mission.onShipDone
        default: return ""
        }
    }

    // True when finishing the mission leaves no flag on (it turns its own
    // flags back off, like "Refuel Trader" or "Report Mu'hari"). The game
    // never treats such a mission as done; it can simply be taken again.
    var isRepeatable: Bool {
        let blank: [Bool] = []
        let everyChoice: [[Int]] = randomChoices.isEmpty ? [[]] : randomChoices[0].indices.map { [$0] }

        return everyChoice.allSatisfy { choices in
            !doneChanges(currentBits: blank, choices: choices).values.contains(true)
        }
    }

    // New values for the flags marking the mission not done would change:
    // everything it can turn on (either side of a random choice included)
    // goes off, except shared flags.
    func notDoneChanges(currentBits: [Bool], isShared: (Int) -> Bool) -> [Int: Bool] {
        var changes: [Int: Bool] = [:]

        for operation in turnedOnOperations {
            guard let flagID = operation.flagID, !isShared(flagID) else { continue }
            guard currentBits.indices.contains(flagID), currentBits[flagID] else { continue }

            changes[flagID] = false
        }

        return changes
    }

    // Shared flags marking the mission not done leaves alone.
    func sharedFlagsLeftOn(currentBits: [Bool], isShared: (Int) -> Bool) -> [Int] {
        let ids: Set<Int> = Set(turnedOnOperations.compactMap(\.flagID).filter { flagID in
            isShared(flagID) && currentBits.indices.contains(flagID) && currentBits[flagID]
        })

        return ids.sorted()
    }

    private var turnedOnOperations: [Operation] {
        steps.flatMap(\.operations)
        .filter { operation in
            switch operation {
            case .set, .toggle: return true
            case .clear, .other: return false
            }
        }
    }

    // Plain words for the common non-flag effects (Nova Bible NCB set
    // operators); anything else is shown as written.
    static func describeEffect(_ token: String) -> String {
        guard let letter = token.first, let number = Int(token.dropFirst()) else { return token }

        switch letter {
        case "S", "s": return "starting mission \(number)"
        case "A", "a": return "aborting mission \(number)"
        case "F", "f": return "failing mission \(number)"
        case "G", "g": return "giving outfit \(number)"
        case "D", "d": return "removing outfit \(number)"
        case "M", "m", "N", "n": return "moving you to system \(number)"
        case "C", "c", "E", "e", "H", "h": return "changing your ship to type \(number)"
        case "K", "k": return "activating rank \(number)"
        case "L", "l": return "removing rank \(number)"
        case "P", "p": return "playing sound \(number)"
        case "Y", "y": return "destroying stellar \(number)"
        case "U", "u": return "restoring stellar \(number)"
        case "Q", "q": return "making you leave the planet"
        case "T", "t": return "renaming your ship"
        case "X", "x": return "marking system \(number) explored"
        default: return token
        }
    }
}
