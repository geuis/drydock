import SwiftUI

// The 10,000 story/plugin flags. Names come from whatever in the scenario
// reads or changes each flag, so both stock Nova and plugin flags read as
// something meaningful.
struct StoryFlagsPane: View {
    @ObservedObject var pilotFile: PilotFile

    @EnvironmentObject private var gameData: GameDataStore

    private enum BrowseMode: String, CaseIterable, Identifiable {
        case set = "Currently On"
        case known = "All Used Flags"

        var id: String { rawValue }
    }

    @State private var browseMode: BrowseMode = .set
    @State private var searchText: String = ""
    @State private var directIndexText: String = ""
    @State private var errorMessage: String?
    @State private var expandedFlagIDs: Set<Int> = []

    var body: some View {
        let flagIDs: [Int] = visibleFlagIDs

        // List, not Form: "All Used Flags" can show hundreds of rows, and a
        // grouped Form builds every one of them up front.
        List {
            Section {
                Picker("Show", selection: $browseMode) {
                    ForEach(BrowseMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Filter by flag number, name, or mission", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            } footer: {
                Text(catalogMessage)
            }

            Section {
                HStack {
                    TextField("Flag number (0 to \(MissionBits.count - 1))", text: $directIndexText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                    Button("Turn On") {
                        applyDirect(true)
                    }
                    .disabled(directIndex == nil)

                    Button("Turn Off") {
                        applyDirect(false)
                    }
                    .disabled(directIndex == nil)
                }
            } header: {
                Text("Set a Flag by Number")
            } footer: {
                Text("For flags a plugin's documentation tells you about that nothing in the loaded game data uses.")
            }

            Section(browseMode.rawValue + " (\(flagIDs.count))") {
                if flagIDs.isEmpty {
                    Text(searchText.isEmpty ? "None." : "No matching flags.")
                        .foregroundStyle(.secondary)
                }

                ForEach(flagIDs, id: \.self) { flagID in
                    flagRow(flagID)
                }
            }
        }
        .editErrorAlert($errorMessage)
    }

    private func flagRow(_ flagID: Int) -> some View {
        let metadata: StoryFlagMetadata? = catalog[flagID]

        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { MissionBits.isSet(flagID, in: pilotFile.workingBytes) },
                set: { isOn in
                    setFlag(flagID, to: isOn)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Story flag \(flagID): \(metadata?.name ?? "Not used by the loaded game data")")
                        .font(.body.weight(.medium))
                }
            }
            // Checkbox, not switch: switches are costly AppKit controls and
            // this list can hold hundreds of rows.
            .toggleStyle(.checkbox)

            if let metadata, !metadata.references.isEmpty {
                let isExpanded: Bool = expandedFlagIDs.contains(flagID)
                let count: Int = metadata.references.count

                // A plain button instead of DisclosureGroup, whose arrow is
                // hidden inside a List on macOS.
                Button {
                    if isExpanded {
                        expandedFlagIDs.remove(flagID)
                    } else {
                        expandedFlagIDs.insert(flagID)
                    }
                } label: {
                    Label(
                        "\(isExpanded ? "Hide" : "Show") what uses it (\(count) item\(count == 1 ? "" : "s"))",
                        systemImage: isExpanded ? "chevron.down" : "chevron.right"
                    )
                }
                .buttonStyle(.link)
                .font(.caption)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(metadata.references, id: \.self) { reference in
                            Text(referenceText(reference))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.leading, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func referenceText(_ reference: StoryFlagReference) -> String {
        let source: String = "\(reference.sourceKind) “\(GameName(reference.sourceName).full)” (ID \(reference.sourceID))"

        switch reference.effect {
        case .requiresSet: return "Needs it on: \(source), for \(reference.event)"
        case .requiresClear: return "Needs it off: \(source), for \(reference.event)"
        case .sets: return "Turns it on: \(source), when \(reference.event)"
        case .clears: return "Turns it off: \(source), when \(reference.event)"
        case .toggles: return "Flips it: \(source), when \(reference.event)"
        }
    }

    // MARK: - Data

    private var catalog: [Int: StoryFlagMetadata] {
        gameData.snapshot?.storyFlags ?? [:]
    }

    private var catalogMessage: String {
        if gameData.isLoading { return "Loading flag names…" }
        if let message = gameData.errorMessage { return message }
        return "\(catalog.count) flags are used by the loaded missions, ships, outfits, and other game data. Names are built from what uses each flag."
    }

    private var visibleFlagIDs: [Int] {
        let base: [Int] = browseMode == .set
            ? MissionBits.setIndices(from: pilotFile.workingBytes)
            : catalog.keys.sorted()
        let query: String = searchText.trimmingCharacters(in: .whitespaces)

        guard !query.isEmpty else { return base }

        return base.filter { flagID in
            guard String(flagID) != query else { return true }
            guard let metadata = catalog[flagID] else { return false }

            return metadata.name.localizedCaseInsensitiveContains(query)
                || metadata.description.localizedCaseInsensitiveContains(query)
                || metadata.references.contains { $0.sourceName.localizedCaseInsensitiveContains(query) }
        }
    }

    private var directIndex: Int? {
        guard let value = Int(directIndexText), (0..<MissionBits.count).contains(value) else { return nil }
        return value
    }

    private func applyDirect(_ isOn: Bool) {
        guard let directIndex else { return }
        setFlag(directIndex, to: isOn)
    }

    private func setFlag(_ flagID: Int, to isOn: Bool) {
        do {
            try pilotFile.setMissionBit(flagID, to: isOn)
        } catch {
            errorMessage = "Could not change story flag \(flagID): \(error.localizedDescription)"
        }
    }
}
