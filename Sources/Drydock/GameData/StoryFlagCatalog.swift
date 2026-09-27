import Foundation

public enum StoryFlagEffect: String, Sendable {
    case requiresSet
    case requiresClear
    case sets
    case clears
    case toggles
}

public struct StoryFlagReference: Hashable, Sendable {
    public let effect: StoryFlagEffect
    public let sourceKind: String
    public let sourceID: Int
    public let sourceName: String
    public let event: String
}

public struct StoryFlagMetadata: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let description: String
    public let references: [StoryFlagReference]
}

// Builds human-readable control-bit metadata from the scenario itself. EV
// Nova does not contain a separate bit-name resource; meaning is encoded in
// the named resources which test and mutate each bit. Deriving the catalog
// also makes it work for total conversions and plugins.
public struct StoryFlagCatalog: Sendable {
    public let flagsByID: [Int: StoryFlagMetadata]

    public init(library: GameDataLibrary) {
        self.init(
            missions: MissionDefinition.decodeAll(from: library),
            outfits: OutfitDefinition.decodeAll(from: library),
            ships: ShipDefinition.decodeAll(from: library),
            timedEvents: TimedEventSource.decodeAll(from: library),
            disasters: DisasterSource.decodeAll(from: library),
            characters: CharacterSource.decodeAll(from: library),
            planets: PlanetSource.decodeAll(from: library),
            systems: SystemSource.decodeAll(from: library),
            fleets: FleetSource.decodeAll(from: library),
            junkTypes: JunkTypeSource.decodeAll(from: library)
        )
    }

    // Extra sources beyond mission/outfit/ship default to empty so existing
    // callers (another engineer's code, and MissionBitsTests) that only pass
    // missions/outfits/ships keep compiling and behaving exactly as before -
    // see the task report for why these particular resource types were
    // chosen (every scenario resource type documented in the Nova Bible as
    // having a control-bit test/set expression field of its own).
    public init(
        missions: [MissionDefinition],
        outfits: [OutfitDefinition],
        ships: [ShipDefinition],
        timedEvents: [TimedEventSource] = [],
        disasters: [DisasterSource] = [],
        characters: [CharacterSource] = [],
        planets: [PlanetSource] = [],
        systems: [SystemSource] = [],
        fleets: [FleetSource] = [],
        junkTypes: [JunkTypeSource] = []
    ) {
        var references: [Int: [StoryFlagReference]] = [:]

        for mission in missions {
            Self.addTestExpression(mission.availBits, sourceKind: "Mission", sourceID: mission.id, sourceName: mission.name, event: "availability", to: &references)
            Self.addSetExpression(mission.onAccept, sourceKind: "Mission", sourceID: mission.id, sourceName: mission.name, event: "accepted", to: &references)
            Self.addSetExpression(mission.onRefuse, sourceKind: "Mission", sourceID: mission.id, sourceName: mission.name, event: "refused", to: &references)
            Self.addSetExpression(mission.onSuccess, sourceKind: "Mission", sourceID: mission.id, sourceName: mission.name, event: "completed", to: &references)
            Self.addSetExpression(mission.onFailure, sourceKind: "Mission", sourceID: mission.id, sourceName: mission.name, event: "failed", to: &references)
            Self.addSetExpression(mission.onAbort, sourceKind: "Mission", sourceID: mission.id, sourceName: mission.name, event: "aborted", to: &references)
            Self.addSetExpression(mission.onShipDone, sourceKind: "Mission", sourceID: mission.id, sourceName: mission.name, event: "ship objective completed", to: &references)
        }

        for outfit in outfits {
            Self.addTestExpression(outfit.availability, sourceKind: "Outfit", sourceID: outfit.id, sourceName: outfit.name, event: "availability", to: &references)
            Self.addSetExpression(outfit.onPurchase, sourceKind: "Outfit", sourceID: outfit.id, sourceName: outfit.name, event: "purchased", to: &references)
            Self.addSetExpression(outfit.onSell, sourceKind: "Outfit", sourceID: outfit.id, sourceName: outfit.name, event: "sold", to: &references)
        }

        for ship in ships {
            Self.addTestExpression(ship.availability, sourceKind: "Ship", sourceID: ship.id, sourceName: ship.name, event: "availability", to: &references)
            Self.addTestExpression(ship.appearOn, sourceKind: "Ship", sourceID: ship.id, sourceName: ship.name, event: "appearance", to: &references)
            Self.addSetExpression(ship.onPurchase, sourceKind: "Ship", sourceID: ship.id, sourceName: ship.name, event: "purchased", to: &references)
            Self.addSetExpression(ship.onCapture, sourceKind: "Ship", sourceID: ship.id, sourceName: ship.name, event: "captured", to: &references)
            Self.addSetExpression(ship.onRetire, sourceKind: "Ship", sourceID: ship.id, sourceName: ship.name, event: "retired", to: &references)
        }

        for event in timedEvents {
            Self.addTestExpression(event.enableOn, sourceKind: "Timed Event", sourceID: event.id, sourceName: event.name, event: "eligible to activate", to: &references)
            Self.addSetExpression(event.onStart, sourceKind: "Timed Event", sourceID: event.id, sourceName: event.name, event: "started", to: &references)
            Self.addSetExpression(event.onEnd, sourceKind: "Timed Event", sourceID: event.id, sourceName: event.name, event: "ended", to: &references)
        }

        for disaster in disasters {
            Self.addTestExpression(disaster.activateOn, sourceKind: "Disaster", sourceID: disaster.id, sourceName: disaster.name, event: "activation", to: &references)
        }

        for character in characters {
            Self.addTestExpression(character.activeOn, sourceKind: "Character", sourceID: character.id, sourceName: character.name, event: "appearance", to: &references)
        }

        for planet in planets {
            Self.addSetExpression(planet.onDominate, sourceKind: "Planet", sourceID: planet.id, sourceName: planet.name, event: "dominated", to: &references)
            Self.addSetExpression(planet.onRelease, sourceKind: "Planet", sourceID: planet.id, sourceName: planet.name, event: "released from domination", to: &references)
            Self.addSetExpression(planet.onDestroy, sourceKind: "Planet", sourceID: planet.id, sourceName: planet.name, event: "destroyed", to: &references)
            Self.addSetExpression(planet.onRegen, sourceKind: "Planet", sourceID: planet.id, sourceName: planet.name, event: "regenerated", to: &references)
        }

        for system in systems {
            Self.addTestExpression(system.visibility, sourceKind: "System", sourceID: system.id, sourceName: system.name, event: "visibility", to: &references)
        }

        for fleet in fleets {
            Self.addTestExpression(fleet.appearOn, sourceKind: "Fleet", sourceID: fleet.id, sourceName: fleet.name, event: "appearance", to: &references)
        }

        for junkType in junkTypes {
            Self.addTestExpression(junkType.buyOn, sourceKind: "Junk Type", sourceID: junkType.id, sourceName: junkType.name, event: "purchase availability", to: &references)
            Self.addTestExpression(junkType.sellOn, sourceKind: "Junk Type", sourceID: junkType.id, sourceName: junkType.name, event: "sale availability", to: &references)
        }

        self.flagsByID = Dictionary(uniqueKeysWithValues: references.map { id, refs in
            let sorted = Array(Set(refs)).sorted {
                ($0.effect.rawValue, $0.sourceKind, $0.sourceID, $0.event) <
                    ($1.effect.rawValue, $1.sourceKind, $1.sourceID, $1.event)
            }
            let metadata = StoryFlagMetadata(
                id: id,
                name: Self.makeName(for: id, references: sorted),
                description: Self.makeDescription(references: sorted),
                references: sorted
            )
            return (id, metadata)
        })
    }

    public subscript(id: Int) -> StoryFlagMetadata? { flagsByID[id] }

    // Parses only Bxxx control-bit operators. Prefix semantics depend on
    // whether the expression is a test or a mutation expression.
    public static func bitOperations(in expression: String, isTest: Bool) -> [(id: Int, effect: StoryFlagEffect)] {
        // Requirements come from the real parser so a negation around a
        // group counts: "!(b275 | b512)" needs both flags off. The
        // character scan below only saw the character right before each
        // flag and reported both as "needs on".
        if isTest, let node = NCBTestExpression.parse(expression).node {
            var result: [(id: Int, effect: StoryFlagEffect)] = []
            collectRequirements(node, isNegated: false, into: &result)
            return result
        }

        if isTest {
            return looseRequirements(in: expression)
        }

        // Set expressions go through the one shared set-expression parser.
        return NCBSetExpression.operations(in: expression).compactMap { operation -> (id: Int, effect: StoryFlagEffect)? in
            switch operation {
            case .set(let id): return (id, .sets)
            case .clear(let id): return (id, .clears)
            case .toggle(let id): return (id, .toggles)
            case .other: return nil
            }
        }
    }

    // Fallback for a test expression the real parser rejects (e.g. an
    // unbalanced parenthesis): still report every flag it mentions, reading
    // a "!" directly before one as "needs off".
    private static func looseRequirements(in expression: String) -> [(id: Int, effect: StoryFlagEffect)] {
        let characters = Array(expression)
        var result: [(id: Int, effect: StoryFlagEffect)] = []
        var index = 0

        while index < characters.count {
            guard characters[index] == "b" || characters[index] == "B" else {
                index += 1
                continue
            }

            var end = index + 1
            while end < characters.count, characters[end].isNumber { end += 1 }
            guard end > index + 1, let id = Int(String(characters[(index + 1)..<end])) else {
                index += 1
                continue
            }

            let prefix = index > 0 ? characters[index - 1] : " "
            result.append((id, prefix == "!" ? .requiresClear : .requiresSet))
            index = end
        }

        return result
    }

    // Walks a parsed requirement, flipping on/off at every "!".
    private static func collectRequirements(_ node: NCBNode, isNegated: Bool, into result: inout [(id: Int, effect: StoryFlagEffect)]) {
        switch node {
        case .bit(let id):
            result.append((id, isNegated ? .requiresClear : .requiresSet))

        case .not(let inner):
            collectRequirements(inner, isNegated: !isNegated, into: &result)

        case .and(let children), .or(let children):
            for child in children {
                collectRequirements(child, isNegated: isNegated, into: &result)
            }

        case .registered, .male, .outfit, .explored:
            break
        }
    }

    private static func addTestExpression(
        _ expression: String,
        sourceKind: String,
        sourceID: Int,
        sourceName: String,
        event: String,
        to references: inout [Int: [StoryFlagReference]]
    ) {
        add(expression, isTest: true, sourceKind: sourceKind, sourceID: sourceID, sourceName: sourceName, event: event, to: &references)
    }

    private static func addSetExpression(
        _ expression: String,
        sourceKind: String,
        sourceID: Int,
        sourceName: String,
        event: String,
        to references: inout [Int: [StoryFlagReference]]
    ) {
        add(expression, isTest: false, sourceKind: sourceKind, sourceID: sourceID, sourceName: sourceName, event: event, to: &references)
    }

    private static func add(
        _ expression: String,
        isTest: Bool,
        sourceKind: String,
        sourceID: Int,
        sourceName: String,
        event: String,
        to references: inout [Int: [StoryFlagReference]]
    ) {
        // Set expressions can wrap two operations in R(<op1> <op2>) to pick
        // one at random and skip the other (Nova Bible, set-expression
        // section) - a "sets"/"clears" reference sourced from inside one of
        // these groups isn't guaranteed to happen, only possible. This is
        // surfaced as a qualifier on the reference's `event` text rather
        // than a new StoryFlagEffect case, since bitOperations already
        // correctly parses only `b`/`B` + digits as a bit reference
        // regardless of surrounding R(...)/parens - there's no parsing bug
        // to fix here, only a description-text nuance to add.
        let randomChoiceIDs: Set<Int> = isTest ? [] : NCBSetExpression.flagIDsInsideRandomChoices(in: expression)

        for operation in bitOperations(in: expression, isTest: isTest) where (0..<MissionBits.count).contains(operation.id) {
            let qualifiedEvent = randomChoiceIDs.contains(operation.id)
                ? "\(event), if the random choice favors it"
                : event

            references[operation.id, default: []].append(StoryFlagReference(
                effect: operation.effect,
                sourceKind: sourceKind,
                sourceID: sourceID,
                sourceName: sourceName,
                event: qualifiedEvent
            ))
        }
    }

    private static func makeName(for id: Int, references: [StoryFlagReference]) -> String {
        let primary = references.first(where: { $0.effect == .sets })
            ?? references.first(where: { $0.effect == .toggles })
            ?? references.first(where: { $0.effect == .clears })
            ?? references.first
        guard let primary else { return "Story Flag \(id)" }

        let cleanName = primary.sourceName.split(separator: ";", maxSplits: 1).first.map(String.init) ?? primary.sourceName

        // A flag many missions turn on (511 "a main storyline is in
        // progress") would otherwise be named after whichever mission sorts
        // first, which reads as if that one mission set it.
        let setterIDs: Set<Int> = Set(
            references
                .filter { $0.sourceKind == "Mission" && ($0.effect == .sets || $0.effect == .toggles) }
                .map(\.sourceID)
        )

        if setterIDs.count > MissionDiagnostics.sharedFlagSetterLimit {
            return "Shared story flag, turned on by \(setterIDs.count) missions such as \(cleanName)"
        }

        let suffix: String
        switch primary.effect {
        case .sets: suffix = primary.event.capitalized
        case .clears: suffix = "Reset when \(primary.event)"
        case .toggles: suffix = "Toggled when \(primary.event)"
        case .requiresSet, .requiresClear: suffix = "Requirement"
        }
        return "\(cleanName) (\(suffix))"
    }

    private static func makeDescription(references: [StoryFlagReference]) -> String {
        let statements = references.prefix(8).map { reference -> String in
            switch reference.effect {
            case .requiresSet:
                return "\(reference.sourceKind) “\(reference.sourceName)” requires this story flag to be on for \(reference.event)."
            case .requiresClear:
                return "\(reference.sourceKind) “\(reference.sourceName)” requires this story flag to be off for \(reference.event)."
            case .sets:
                return "Set when \(reference.sourceKind.lowercased()) “\(reference.sourceName)” is \(reference.event)."
            case .clears:
                return "Cleared when \(reference.sourceKind.lowercased()) “\(reference.sourceName)” is \(reference.event)."
            case .toggles:
                return "Toggled when \(reference.sourceKind.lowercased()) “\(reference.sourceName)” is \(reference.event)."
            }
        }
        let remainder = references.count - statements.count
        return statements.joined(separator: " ") + (remainder > 0 ? " Plus \(remainder) more references." : "")
    }
}
