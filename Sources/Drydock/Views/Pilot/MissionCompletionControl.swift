import SwiftUI

// A "Done" switch for one mission. Turning it on applies the story flags
// finishing the mission would set; turning it off takes them back (see
// MissionCompletion for the rules). Like every edit, nothing is written to
// disk until the pilot is saved.
struct MissionCompletionControl: View {
    let mission: MissionDefinition
    let status: MissionStatus?
    // Changes each time the story chains are re-evaluated; `status` is up
    // to date for the latest edit once it does.
    let evaluationCount: Int
    @ObservedObject var pilotFile: PilotFile
    let storyFlags: [Int: StoryFlagMetadata]

    @State private var choosingTrack = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var awaitingDoneCheck = false

    private var completion: MissionCompletion {
        MissionCompletion(mission: mission)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { status == .completed },
                set: { isDone in
                    if isDone {
                        startMarkingDone()
                    } else {
                        markNotDone()
                    }
                }
            )) {
                Text("Done")
                    .fontWeight(.medium)
            }
            .toggleStyle(.switch)
            .help("Turns on (or back off) the story flags finishing this mission sets, which is how the game remembers it and unlocks what comes next.")
            .disabled(completion.isRepeatable)

            if completion.isRepeatable {
                Text("Finishing this mission leaves no story flag on, so the game never records it as done; it can just be taken again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let resultMessage {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Which way did it go?", isPresented: $choosingTrack, titleVisibility: .visible) {
            ForEach(Array(trackOptions.enumerated()), id: \.offset) { index, label in
                Button(label) {
                    markDone(choices: [index])
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Finishing this mission in the game picks one of these at random.")
        }
        .editErrorAlert($errorMessage)
        // The new status arrives after the flags change, and may be the same
        // as before (a blocked mission can stay blocked), so wait for the
        // re-evaluation rather than a status change. If it isn't "done", say
        // why rather than leaving the switch to flip back silently.
        .onChange(of: evaluationCount) { _, _ in
            guard awaitingDoneCheck else { return }

            awaitingDoneCheck = false
            explainIfStillNotDone(status)
        }
    }

    // MARK: - Actions

    private func startMarkingDone() {
        if completion.randomChoices.isEmpty {
            markDone(choices: [])
        } else {
            choosingTrack = true
        }
    }

    private func markDone(choices: [Int]) {
        let changes: [Int: Bool] = completion.doneChanges(currentBits: MissionBits.decodeAll(from: pilotFile.workingBytes), choices: choices)

        apply(changes) {
            var parts: [String] = [describe(changes, empty: "Its story flags were already on.")]

            let skipped: [String] = completion.otherEffects.map(MissionCompletion.describeEffect)
            if !skipped.isEmpty {
                parts.append("Not applied (not a story flag): \(skipped.joined(separator: ", ")).")
            }

            if pilotFile.missionSlots.contains(where: { $0.isActive && $0.missionID == mission.id }) {
                parts.append("It's still in your active missions; remove it on Current Missions.")
            }

            return parts.joined(separator: " ")
        }

        // With no flag change there's no re-evaluation to wait for.
        if changes.isEmpty {
            explainIfStillNotDone(status)
        } else {
            awaitingDoneCheck = true
        }
    }

    private func explainIfStillNotDone(_ currentStatus: MissionStatus?) {
        guard currentStatus != .completed, let resultMessage else { return }

        self.resultMessage = resultMessage + " It still doesn't count as done: an earlier step's story flags aren't on (see Requirements below)."
    }

    private func markNotDone() {
        let current: [Bool] = MissionBits.decodeAll(from: pilotFile.workingBytes)
        let isShared: (Int) -> Bool = { MissionDiagnostics.isSharedFlag($0, storyFlags: storyFlags) }
        let changes: [Int: Bool] = completion.notDoneChanges(currentBits: current, isShared: isShared)
        let sharedLeftOn: [Int] = completion.sharedFlagsLeftOn(currentBits: current, isShared: isShared)

        apply(changes) {
            var parts: [String] = [describe(changes, empty: "None of its own story flags were on.")]

            if !sharedLeftOn.isEmpty {
                parts.append("Left on shared \(MissionDiagnostics.storyFlagsText(sharedLeftOn)), which other missions also use; change \(sharedLeftOn.count == 1 ? "it" : "them") on Story Flags if needed.")
            }

            return parts.joined(separator: " ")
        }
    }

    private func apply(_ changes: [Int: Bool], message: () -> String) {
        do {
            try pilotFile.setMissionBits(changes)
            resultMessage = message()
        } catch {
            errorMessage = "Could not change the story flags: \(error.localizedDescription)"
        }
    }

    // MARK: - Wording

    // One label per option of the first random choice, named after the
    // missions waiting for that option's flag.
    private var trackOptions: [String] {
        guard let options = completion.randomChoices.first else { return [] }

        return options.map { operation in
            guard let flagID = operation.flagID else { return "Option \(operation)" }

            let waiting: [String] = (storyFlags[flagID]?.references ?? [])
                .filter { $0.sourceKind == "Mission" && $0.effect == .requiresSet }
                .map { MissionDiagnostics.displayName($0.sourceName, fallbackID: $0.sourceID) }

            guard let first = waiting.first else { return "Turn on story flag \(flagID)" }
            return "Toward '\(first)' (story flag \(flagID))"
        }
    }

    private func describe(_ changes: [Int: Bool], empty: String) -> String {
        let turnedOn: [Int] = changes.filter(\.value).map(\.key).sorted()
        let turnedOff: [Int] = changes.filter { !$0.value }.map(\.key).sorted()
        var parts: [String] = []

        if !turnedOn.isEmpty {
            parts.append("Turned on \(MissionDiagnostics.storyFlagsText(turnedOn)).")
        }

        if !turnedOff.isEmpty {
            parts.append("Turned off \(MissionDiagnostics.storyFlagsText(turnedOff)).")
        }

        return parts.isEmpty ? empty : parts.joined(separator: " ")
    }
}
