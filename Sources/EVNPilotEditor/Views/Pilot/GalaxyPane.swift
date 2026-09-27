import SwiftUI

// A named entry in one of the pilot file's per-resource arrays. Arrays are
// indexed by (resource ID - 128).
struct NamedSlot: Identifiable, Hashable {
    let id: Int
    let index: Int
    let title: String
    let note: String?
}

enum NamedSlots {
    // Every named resource of `type` that fits in an array of `count`
    // entries, plus any unnamed slot whose value isn't the default (so
    // plugin data the loaded files don't cover is never hidden).
    static func build(type: String, count: Int, names: ResourceNameIndex?, isNonDefault: (Int) -> Bool) -> [NamedSlot] {
        var slots: [NamedSlot] = []
        var covered: Set<Int> = []

        for entry in names?.entries(ofType: type) ?? [] {
            let index: Int = entry.id - 128
            guard index >= 0, index < count else { continue }

            let name: GameName = GameName(entry.name)
            slots.append(NamedSlot(id: entry.id, index: index, title: name.title, note: name.note))
            covered.insert(index)
        }

        for index in 0..<count where !covered.contains(index) && isNonDefault(index) {
            slots.append(NamedSlot(id: index + 128, index: index, title: "Unnamed \(index + 128)", note: "not in the loaded game data"))
        }

        return slots.sorted { $0.id < $1.id }
    }

    static func matches(_ slot: NamedSlot, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return slot.title.localizedCaseInsensitiveContains(query)
            || (slot.note?.localizedCaseInsensitiveContains(query) ?? false)
            || String(slot.id) == query
    }
}

struct GalaxyPane: View {
    @ObservedObject var pilotFile: PilotFile

    @EnvironmentObject private var gameData: GameDataStore

    private enum Tab: String, CaseIterable, Identifiable {
        case systems = "Systems"
        case stellars = "Planets & Stations"

        var id: String { rawValue }
    }

    @State private var tab: Tab = .systems
    @State private var searchText: String = ""
    @State private var onlyChanged = false
    @State private var errorMessage: String?
    @State private var showingExploreConfirmation = false
    @State private var showingRecordConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ListFilterBar(searchText: $searchText, onlyChanged: $onlyChanged, onlyChangedLabel: tab == .systems ? "Explored or with a record" : "Changed only")

                if tab == .systems {
                    HStack {
                        Button("Explore All Systems…") {
                            showingExploreConfirmation = true
                        }

                        Button("Clear Criminal Records…") {
                            showingRecordConfirmation = true
                        }

                        Spacer()
                    }
                }
            }
            .padding()

            Divider()

            switch tab {
            case .systems:
                systemsList

            case .stellars:
                stellarsList
            }
        }
        .confirmationDialog("Mark every system as explored?", isPresented: $showingExploreConfirmation, titleVisibility: .visible) {
            Button("Explore All") {
                exploreAll()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unexplored systems become visited. Systems you've already visited or landed in are left alone.")
        }
        .confirmationDialog("Clear every negative legal record?", isPresented: $showingRecordConfirmation, titleVisibility: .visible) {
            Button("Clear Records") {
                clearCriminalRecords()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every system where your record is below zero is reset to neutral. Good records are kept.")
        }
        .editErrorAlert($errorMessage)
    }

    // MARK: - Systems

    private var systemsList: some View {
        let bytes: Data = pilotFile.workingBytes
        let exploration: [Int16] = PilotExploration.decodeExploration(from: bytes)
        let legal: [Int16] = PilotExploration.decodeLegalStatus(from: bytes)
        let reinforcements: [Int16] = PilotUniverseState.decodeReinforcements(from: bytes)
        let query: String = searchText.trimmingCharacters(in: .whitespaces)

        let slots: [NamedSlot] = NamedSlots.build(type: ResourceNameIndex.systems, count: exploration.count, names: gameData.snapshot?.names) { index in
            exploration[index] > 0 || value(legal, index) != 0
        }
        .filter { slot in
            guard NamedSlots.matches(slot, query: query) else { return false }
            guard onlyChanged else { return true }
            return exploration[slot.index] > 0 || value(legal, slot.index) != 0
        }

        return List {
            Section {
                ForEach(slots) { slot in
                    HStack {
                        slotTitle(slot)

                        Spacer()

                        Picker("Explored", selection: Binding(
                            get: { max(Int16(0), min(exploration[slot.index], 2)) },
                            set: { newValue in
                                perform {
                                    try pilotFile.setExploration(newValue, at: slot.index)
                                }
                            }
                        )) {
                            Text("Unexplored").tag(Int16(0))
                            Text("Visited").tag(Int16(1))
                            Text("Landed").tag(Int16(2))
                        }
                        .labelsHidden()
                        .frame(width: 120)

                        Text("Record")
                            .foregroundStyle(.secondary)

                        IntegerField(value: Int(value(legal, slot.index)), range: Int(Int16.min)...Int(Int16.max), commit: { newValue in
                            try pilotFile.setLegalStatus(Int16(newValue), at: slot.index)
                        }, onError: report, width: 70)

                        Text("Reinforce in")
                            .foregroundStyle(.secondary)

                        IntegerField(value: Int(value(reinforcements, slot.index)), range: Int(Int16.min)...Int(Int16.max), commit: { newValue in
                            try pilotFile.setReinforcements(Int16(newValue), at: slot.index)
                        }, onError: report, width: 56)
                    }
                }
            } header: {
                Text("\(slots.count) systems")
            } footer: {
                Text("Legal record: positive is good standing, negative means you're wanted. \"Reinforce in\" is the number of days until the system's defenders come back.")
            }
        }
    }

    // MARK: - Planets and stations

    private var stellarsList: some View {
        let bytes: Data = pilotFile.workingBytes
        let dominated: [Bool] = PilotExploration.decodeStelDominated(from: bytes)
        let defenders: [Int16] = PilotUniverseState.decodeStelShipCount(from: bytes)
        let annoyance: [Int16] = PilotUniverseState.decodeStelAnnoyance(from: bytes)
        let destroyed: [Int16] = PilotUniverseState.decodeStelDestroyed(from: bytes)
        let query: String = searchText.trimmingCharacters(in: .whitespaces)

        let isChanged: (Int) -> Bool = { index in
            (dominated.indices.contains(index) && dominated[index])
                || self.value(annoyance, index) != 0
                || self.value(destroyed, index) >= 0
        }

        let slots: [NamedSlot] = NamedSlots.build(type: ResourceNameIndex.stellars, count: dominated.count, names: gameData.snapshot?.names, isNonDefault: isChanged)
            .filter { slot in
                guard NamedSlots.matches(slot, query: query) else { return false }
                return !onlyChanged || isChanged(slot.index)
            }

        return List {
            Section {
                ForEach(slots) { slot in
                    HStack {
                        slotTitle(slot)

                        Spacer()

                        Toggle("Dominated", isOn: Binding(
                            get: { dominated.indices.contains(slot.index) && dominated[slot.index] },
                            set: { isOn in
                                perform {
                                    try pilotFile.setStelDominated(isOn, at: slot.index)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)

                        Text("Defenders")
                            .foregroundStyle(.secondary)

                        IntegerField(value: Int(value(defenders, slot.index)), range: Int(Int16.min)...Int(Int16.max), commit: { newValue in
                            try pilotFile.setStelShipCount(Int16(newValue), at: slot.index)
                        }, onError: report, width: 56)

                        Text("Annoyance")
                            .foregroundStyle(.secondary)

                        IntegerField(value: Int(value(annoyance, slot.index)), range: Int(Int16.min)...Int(Int16.max), commit: { newValue in
                            try pilotFile.setStelAnnoyance(Int16(newValue), at: slot.index)
                        }, onError: report, width: 56)

                        Text("Destroyed")
                            .foregroundStyle(.secondary)

                        IntegerField(value: Int(value(destroyed, slot.index, fallback: -1)), range: Int(Int16.min)...Int(Int16.max), commit: { newValue in
                            try pilotFile.setStelDestroyed(Int16(newValue), at: slot.index)
                        }, onError: report, width: 56)
                    }
                }
            } header: {
                Text("\(slots.count) planets and stations")
            } footer: {
                Text("Defenders: defense ships remaining. Annoyance: how close a dominated world is to rebelling. Destroyed: days until it's rebuilt, or -1 if it's intact.")
            }
        }
    }

    // MARK: - Bulk actions

    private func exploreAll() {
        let exploration: [Int16] = PilotExploration.decodeExploration(from: pilotFile.workingBytes)
        let slots: [NamedSlot] = NamedSlots.build(type: ResourceNameIndex.systems, count: exploration.count, names: gameData.snapshot?.names) { _ in false }

        perform {
            for slot in slots where exploration[slot.index] <= 0 {
                try pilotFile.setExploration(1, at: slot.index)
            }
        }
    }

    private func clearCriminalRecords() {
        let legal: [Int16] = PilotExploration.decodeLegalStatus(from: pilotFile.workingBytes)

        perform {
            for index in legal.indices where legal[index] < 0 {
                try pilotFile.setLegalStatus(0, at: index)
            }
        }
    }

    // MARK: - Helpers

    private func slotTitle(_ slot: NamedSlot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(slot.title)
                .lineLimit(1)

            Text([slot.note, "ID \(slot.id)"].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 160, alignment: .leading)
    }

    private func value(_ array: [Int16], _ index: Int, fallback: Int16 = 0) -> Int16 {
        array.indices.contains(index) ? array[index] : fallback
    }

    private func report(_ message: String) {
        errorMessage = message
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
