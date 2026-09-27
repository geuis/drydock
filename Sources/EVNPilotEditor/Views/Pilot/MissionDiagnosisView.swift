import SwiftUI

// Everything known about why one mission is or isn't available to this
// pilot, with the story flags involved exposed as switches so a stuck
// chain can be fixed on the spot.
struct MissionDiagnosisView: View {
    let mission: MissionDefinition
    let diagnosis: MissionDiagnosis?
    @ObservedObject var pilotFile: PilotFile
    let snapshot: GameDataSnapshot
    let onSelectMission: (Int) -> Void

    @State private var errorMessage: String?
    @State private var pendingFix: PendingFix?
    // Shown above the checklist, since a successful fix removes the lock
    // line it came from.
    @State private var lastFixMessage: String?

    // A lock fix waiting for the user to confirm its preview.
    private struct PendingFix: Identifiable {
        let issueID: String
        let fix: LockFix
        var id: String { issueID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(statusSentence)
                .font(.callout)

            checklist

            if !shownIssues.isEmpty {
                issuesSection(shownIssues)
            }

            requirementsSection

            flagsSection

            linksSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .editErrorAlert($errorMessage)
        .onChange(of: mission.id) { _, _ in
            lastFixMessage = nil
        }
        .confirmationDialog(
            "Fix this in the editor?",
            isPresented: Binding(get: { pendingFix != nil }, set: { if !$0 { pendingFix = nil } }),
            titleVisibility: .visible,
            presenting: pendingFix
        ) { pending in
            Button("Apply") {
                applyFix(pending)
            }

            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(fixPreview(pending.fix))
        }
    }

    // MARK: - Summary

    private var statusSentence: String {
        guard let diagnosis else { return "Not evaluated yet." }

        switch diagnosis.status {
        case .active:
            return "This mission is in one of your mission slots right now."

        case .available:
            return "Every requirement the editor can check is met. It still has to be offered in the right place (below), and some missions only appear some of the time."

        case .completed:
            return "Most likely already done: the story flag this mission turns on when it finishes is already on."

        case .blocked:
            return "Not available yet. The items marked in red below are what's stopping it."

        case .impossible:
            return "This mission can't become available with the loaded game data. The reasons are below."
        }
    }

    // MARK: - Checklist

    // Everything that decides whether the mission is offered, one line
    // each, marked met or unmet. Missions already done or in progress only
    // need the "where" part.
    private var checklist: some View {
        let isSettled: Bool = diagnosis?.status == .completed || diagnosis?.status == .active

        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle(isSettled ? "Where it's offered" : "How to get this mission")

            if let lastFixMessage {
                Text(lastFixMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isSettled {
                ForEach(checklistIssues) { issue in
                    issueRow(issue)
                }

                storyRequirementLine
            }

            checkLine(
                "Offered at \(MissionPlaces.offeredAt(mission.availStel, names: snapshot.names)), \(MissionPlaces.offerPlace(mission.availLoc)). Go there to see it.",
                state: .info
            )

            if mission.availRandom > 0, mission.availRandom < 100 {
                checkLine("Offered only \(mission.availRandom)% of the time. The roll is repeated each time you arrive in a system, so keep coming back.", state: .info)
            }

            if !isSettled, mission.availRating >= 0 {
                let isMet: Bool = Int(pilotFile.combatRating) >= Int(mission.availRating)
                checkLine(
                    isMet
                        ? "Combat rating \(mission.availRating) or more (yours is \(pilotFile.combatRating))."
                        : "Needs combat rating \(mission.availRating); yours is \(pilotFile.combatRating). Win more fights, or raise it on Pilot & Ship.",
                    state: isMet ? .met : .unmet
                )
            }

            if !isSettled, hasShipRules, !checklistIssues.contains(where: { $0.id.hasPrefix("ship-") }) {
                checkLine("Your ship meets this mission's ship rules (cargo space, ship type, fuel).", state: .met)
            }
        }
    }

    // The storyline lock and ship problems, shown as checklist lines
    // rather than repeated under "What's going on".
    private var checklistIssues: [MissionIssue] {
        (diagnosis?.issues ?? []).filter(Self.isChecklistIssue)
    }

    private static func isChecklistIssue(_ issue: MissionIssue) -> Bool {
        issue.id.hasPrefix("lock-") || issue.id.hasPrefix("ship-")
    }

    private var hasShipRules: Bool {
        let shipFlags: UInt16 = MissionDefinition.flagDrainsFuel | MissionDefinition.flagNotForCargoShips | MissionDefinition.flagNotForWarships
        return mission.flags & shipFlags != 0 || mission.flags2 & MissionDefinition.flag2NeedsCargoSpace != 0
    }

    @ViewBuilder
    private var storyRequirementLine: some View {
        if mission.availBits.trimmingCharacters(in: .whitespaces).isEmpty {
            checkLine("No story-flag requirements.", state: .met)
        } else if let explanation = diagnosis?.explanation {
            if explanation.value {
                checkLine("Story requirements are all met.", state: .met)
            } else {
                let hasLock: Bool = checklistIssues.contains { $0.id.hasPrefix("lock-") }
                checkLine(
                    hasLock
                        ? "Story requirements aren't met. The lock above is part of it; the full list is under Requirements."
                        : "Story requirements aren't met yet. Earlier story steps need doing first; see Requirements below.",
                    state: .unmet
                )
            }
        }
    }

    private enum CheckState {
        case met
        case unmet
        case info
    }

    private func checkLine(_ text: String, state: CheckState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch state {
            case .met:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .unmet:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)

            case .info:
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }

            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Issues

    // The "where it's offered" section above already covers these, with
    // real place names instead of ID numbers.
    private static let issuesShownElsewhere: Set<String> = ["avail-location", "avail-random", "avail-rating"]

    private var shownIssues: [MissionIssue] {
        let isSettled: Bool = diagnosis?.status == .completed || diagnosis?.status == .active

        return (diagnosis?.issues ?? []).filter { issue in
            !Self.issuesShownElsewhere.contains(issue.id) && (isSettled || !Self.isChecklistIssue(issue))
        }
    }

    private func issuesSection(_ issues: [MissionIssue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("What's going on")

            ForEach(issues) { issue in
                issueRow(issue)
            }
        }
    }

    private func issueRow(_ issue: MissionIssue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: issue.severity.symbolName)
                .foregroundStyle(issue.severity.color)

            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title)
                    .font(.callout.weight(.semibold))

                if !issue.detail.isEmpty {
                    Text(issue.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !issue.relatedMissionIDs.isEmpty {
                    missionLinkRow(issue.relatedMissionIDs)
                }

                if let fix = issue.fix {
                    Button(fixLabel(fix)) {
                        pendingFix = PendingFix(issueID: issue.id, fix: fix)
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Lock fixes

    private func fixLabel(_ fix: LockFix) -> String {
        switch fix {
        case .missionOutcome(let missionID, let event):
            return "Fix in editor: do what \(Self.gerund(event)) '\(missionName(missionID))' would have done"

        case .clearFlags(let flagIDs):
            return "Fix in editor: turn off \(MissionDiagnostics.storyFlagsText(flagIDs))"
        }
    }

    // The flag changes a fix makes to the pilot as it is now, plus the
    // copied outcome's other effects, which the editor doesn't apply.
    private func fixPlan(_ fix: LockFix) -> (changes: [Int: Bool], skipped: [String], hasRandomChoice: Bool) {
        let current: [Bool] = MissionBits.decodeAll(from: pilotFile.workingBytes)

        switch fix {
        case .missionOutcome(let missionID, let event):
            guard let source = snapshot.missionResolver.mission(id: missionID) else { return ([:], [], false) }

            let steps: [MissionCompletion.Step] = MissionCompletion.parse(MissionCompletion.expression(for: event, of: source))
            let hasRandomChoice: Bool = steps.contains { step in
                if case .randomChoice = step { return true }
                return false
            }

            return (
                MissionCompletion.changes(for: steps, currentBits: current, choices: []),
                MissionCompletion.otherEffects(in: steps).map(MissionCompletion.describeEffect),
                hasRandomChoice
            )

        case .clearFlags(let flagIDs):
            let changes: [Int: Bool] = Dictionary(uniqueKeysWithValues: flagIDs
                .filter { current.indices.contains($0) && current[$0] }
                .map { ($0, false) })
            return (changes, [], false)
        }
    }

    private func fixPreview(_ fix: LockFix) -> String {
        let plan = fixPlan(fix)
        let changesText: String = Self.describeChanges(plan.changes, verbs: ("turns on", "turns off"), empty: "no story flags would change")
        var parts: [String] = [changesText.prefix(1).uppercased() + changesText.dropFirst() + "."]

        if plan.hasRandomChoice {
            parts.append("That outcome picks between story flags at random; the first option is used.")
        }

        if !plan.skipped.isEmpty {
            parts.append("Not applied (not a story flag): \(plan.skipped.joined(separator: ", ")).")
        }

        parts.append("Nothing is written to the pilot file until you save.")
        return parts.joined(separator: " ")
    }

    private func applyFix(_ pending: PendingFix) {
        let changes: [Int: Bool] = fixPlan(pending.fix).changes

        do {
            try pilotFile.setMissionBits(changes)
            lastFixMessage = "Editor fix applied: " + Self.describeChanges(changes, verbs: ("turned on", "turned off"), empty: "no story flags needed changing") + ". Save to keep it."
        } catch {
            errorMessage = "Could not change the story flags: \(error.localizedDescription)"
        }
    }

    // "turns off story flag 511 and turns on story flag 600", or `empty`.
    private static func describeChanges(_ changes: [Int: Bool], verbs: (on: String, off: String), empty: String) -> String {
        let turnedOn: [Int] = changes.filter(\.value).map(\.key).sorted()
        let turnedOff: [Int] = changes.filter { !$0.value }.map(\.key).sorted()
        var parts: [String] = []

        if !turnedOff.isEmpty {
            parts.append("\(verbs.off) \(MissionDiagnostics.storyFlagsText(turnedOff))")
        }

        if !turnedOn.isEmpty {
            parts.append("\(verbs.on) \(MissionDiagnostics.storyFlagsText(turnedOn))")
        }

        return parts.isEmpty ? empty : parts.joined(separator: " and ")
    }

    // "failed" -> "failing", for "do what failing 'X' would have done".
    private static func gerund(_ event: String) -> String {
        switch event {
        case "completed": return "completing"
        case "failed": return "failing"
        case "aborted": return "aborting"
        case "refused": return "refusing"
        case "accepted": return "accepting"
        case "ship objective completed": return "finishing the ship objective of"
        default: return event
        }
    }

    private func missionName(_ missionID: Int) -> String {
        snapshot.missionResolver.mission(id: missionID).map { GameName($0.name).title } ?? "mission \(missionID)"
    }

    // MARK: - Requirements

    @ViewBuilder
    private var requirementsSection: some View {
        let expression: String = mission.availBits.trimmingCharacters(in: .whitespaces)

        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Requirements")

            if expression.isEmpty {
                Text("No story-flag requirements.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let explanation = diagnosis?.explanation {
                if diagnosis?.status == .active {
                    // Accepting a mission often turns flags on, so lines
                    // can read as unmet now even though they were met.
                    Text("You already have this mission. These are what it needed to be offered, checked against your story flags now; accepting it may have changed some of them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                RequirementNodeView(explanation: explanation, describe: describe)

                Text("Game expression: \(expression)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text("Couldn't read this expression: \(expression)")
                    .font(.callout)
                    .foregroundStyle(.orange)

                if let parseError = diagnosis?.parseError {
                    Text(parseError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func describe(_ term: NCBTermEvaluation, negated: Bool) -> String {
        switch term.kind {
        case .bit(let flagID):
            let name: String = snapshot.storyFlags[flagID]?.name ?? "not used elsewhere"
            return "Story flag \(flagID) is \(negated ? "off" : "on") (\(name))"

        case .outfit(let outfitID):
            let name: String = outfitName(outfitID)
            return negated ? "Outfit: doesn't own \(name)" : "Outfit: owns \(name)"

        case .explored(let systemID):
            let name: String = snapshot.names.name(type: ResourceNameIndex.systems, id: systemID).map { GameName($0).title } ?? "system \(systemID)"
            return negated ? "Exploration: hasn't explored \(name)" : "Exploration: has explored \(name)"

        case .male:
            return negated ? "Pilot gender: female" : "Pilot gender: male"

        case .registered(let days):
            return "Game registration: registered or under \(days) days played (assumed true)"
        }
    }

    // MARK: - Flag switches

    @ViewBuilder
    private var flagsSection: some View {
        let flagIDs: [Int] = involvedFlagIDs

        if !flagIDs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionTitle("Story flags involved")

                ForEach(flagIDs, id: \.self) { flagID in
                    Toggle(isOn: Binding(
                        get: { MissionBits.isSet(flagID, in: pilotFile.workingBytes) },
                        set: { isOn in
                            do {
                                try pilotFile.setMissionBit(flagID, to: isOn)
                            } catch {
                                errorMessage = "Could not change story flag \(flagID): \(error.localizedDescription)"
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Story flag \(flagID)")
                            Text(snapshot.storyFlags[flagID]?.name ?? "Not used by anything else in the loaded game data")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                }

                Text("Flipping a story flag here changes the pilot immediately (save to keep it).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Flags this mission tests, plus any an issue points at, in number order.
    private var involvedFlagIDs: [Int] {
        var ids: Set<Int> = []

        for issue in diagnosis?.issues ?? [] {
            ids.formUnion(issue.relatedFlagIDs)
        }

        if let explanation = diagnosis?.explanation {
            ids.formUnion(Self.flagIDs(in: explanation))
        }

        return ids.sorted()
    }

    private static func flagIDs(in explanation: NCBExplanation) -> [Int] {
        switch explanation {
        case .term(let term):
            if case .bit(let id) = term.kind {
                return [id]
            }
            return []

        case .not(let inner, _):
            return flagIDs(in: inner)

        case .all(let children, _), .any(let children, _):
            return children.flatMap { flagIDs(in: $0) }
        }
    }

    // MARK: - Links

    @ViewBuilder
    private var linksSection: some View {
        let successors: [MissionDefinition] = snapshot.missionResolver.successors(of: mission)
        let predecessors: [MissionDefinition] = snapshot.missionResolver.predecessors(of: mission)

        if !successors.isEmpty || !predecessors.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionTitle("Story links")

                ForEach(predecessors, id: \.id) { predecessor in
                    linkButton(
                        prefix: "Started when",
                        mission: predecessor,
                        suffix: MissionLinks.triggerLabel(from: predecessor, to: mission.id, resolver: snapshot.missionResolver)
                    )
                }

                ForEach(successors, id: \.id) { successor in
                    linkButton(
                        prefix: "Starts",
                        mission: successor,
                        suffix: "when this is " + MissionLinks.triggerLabel(from: mission, to: successor.id, resolver: snapshot.missionResolver).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                    )
                }
            }
        }
    }

    private func linkButton(prefix: String, mission linked: MissionDefinition, suffix: String) -> some View {
        HStack(spacing: 4) {
            Text(prefix)
                .foregroundStyle(.secondary)

            Button(GameName(linked.name).title) {
                onSelectMission(linked.id)
            }
            .buttonStyle(.link)

            Text(suffix)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func missionLinkRow(_ missionIDs: [Int]) -> some View {
        HStack(spacing: 8) {
            ForEach(missionIDs.prefix(6), id: \.self) { missionID in
                Button(snapshot.missionResolver.mission(id: missionID).map { GameName($0.name).title } ?? "Mission \(missionID)") {
                    onSelectMission(missionID)
                }
                .buttonStyle(.link)
            }

            if missionIDs.count > 6 {
                Text("+\(missionIDs.count - 6) more")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func outfitName(_ outfitID: Int) -> String {
        snapshot.outfitsByID[outfitID].map { GameName($0.name).title } ?? "outfit \(outfitID)"
    }
}

// Renders an availability expression as nested "all of / any of" groups,
// each line marked met or unmet for the current pilot.
private struct RequirementNodeView: View {
    let explanation: NCBExplanation
    let describe: (NCBTermEvaluation, Bool) -> String

    var body: some View {
        node(explanation)
    }

    private func node(_ explanation: NCBExplanation) -> AnyView {
        switch explanation {
        case .term(let term):
            return AnyView(line(describe(term, false), met: term.value, assumed: term.isAssumed))

        case .not(let inner, let value):
            // "not <single condition>" reads better as one negated line.
            if case .term(let term) = inner {
                return AnyView(line(describe(term, true), met: value, assumed: term.isAssumed))
            }

            return AnyView(group("None of these may be true", value: value, children: [inner]))

        case .all(let children, let value):
            return AnyView(group("All of these", value: value, children: children))

        case .any(let children, let value):
            return AnyView(group("At least one of these", value: value, children: children))
        }
    }

    private func group(_ title: String, value: Bool, children: [NCBExplanation]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            line(title, met: value, assumed: false)
                .fontWeight(.medium)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(children.indices, id: \.self) { index in
                    node(children[index])
                }
            }
            .padding(.leading, 18)
        }
    }

    private func line(_ text: String, met: Bool, assumed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: assumed ? "questionmark.circle" : (met ? "checkmark.circle.fill" : "xmark.circle.fill"))
                .foregroundStyle(assumed ? Color.secondary : (met ? Color.green : Color.red))

            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Plain-English versions of a mission's "where" fields, using the Nova
// Bible's documented value ranges and the loaded names.
enum MissionPlaces {
    static func offeredAt(_ availStel: Int16, names: ResourceNameIndex) -> String {
        let value: Int = Int(availStel)

        switch value {
        case -1:
            return "Any inhabited planet or station"

        case 128...2175:
            return names.name(type: ResourceNameIndex.stellars, id: value).map { GameName($0).title } ?? "Planet or station \(value)"

        case 5000...7047:
            return "A planet in a system next to \(systemName(value - 5000 + 128, names: names))"

        case 9999...10255:
            return "Any planet of \(governmentName(value - 10000, names: names))"

        case 15000...15255:
            return "Any planet of an ally of \(governmentName(value - 15000, names: names))"

        case 20000...20255:
            return "Any planet not belonging to \(governmentName(value - 20000, names: names))"

        case 25000...25255:
            return "Any planet of an enemy of \(governmentName(value - 25000, names: names))"

        case 30000...30255:
            return "Any planet of \(governmentName(value - 30000, names: names)) or its class"

        case 31000...31255:
            return "Any planet not of \(governmentName(value - 31000, names: names)) or its class"

        default:
            return "Location code \(value)"
        }
    }

    static func offerPlace(_ availLoc: Int16) -> String {
        switch availLoc {
        case 0: return "at the mission computer"
        case 1: return "in the bar"
        case 2: return "offered by a ship in space"
        case 3: return "in the spaceport"
        case 4: return "in the trade center"
        case 5: return "in the shipyard"
        case 6: return "in the outfitter"
        default: return "at offer place \(availLoc)"
        }
    }

    // Government codes store (government ID - 128); -1 means independent.
    private static func governmentName(_ index: Int, names: ResourceNameIndex) -> String {
        guard index >= 0 else { return "independents" }

        let governmentID: Int = index + 128
        return names.name(type: ResourceNameIndex.governments, id: governmentID).map { GameName($0).title } ?? "government \(governmentID)"
    }

    private static func systemName(_ systemID: Int, names: ResourceNameIndex) -> String {
        names.name(type: ResourceNameIndex.systems, id: systemID).map { GameName($0).title } ?? "system \(systemID)"
    }
}
