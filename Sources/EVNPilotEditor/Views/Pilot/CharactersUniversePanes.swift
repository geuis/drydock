import SwiftUI

// Named characters ("përs"): whether each is still around and whether they
// hold a grudge against the pilot.
struct CharactersPane: View {
    @ObservedObject var pilotFile: PilotFile

    @EnvironmentObject private var gameData: GameDataStore

    @State private var searchText: String = ""
    @State private var onlyChanged = false
    @State private var errorMessage: String?

    var body: some View {
        let bytes: Data = pilotFile.workingBytes
        let alive: [Int16] = PilotUniverseState.decodePersonAlive(from: bytes)
        let grudge: [Int16] = PilotUniverseState.decodePersonGrudge(from: bytes)
        let query: String = searchText.trimmingCharacters(in: .whitespaces)

        let isChanged: (Int) -> Bool = { index in
            !(alive.indices.contains(index) && alive[index] != 0) || (grudge.indices.contains(index) && grudge[index] != 0)
        }

        let slots: [NamedSlot] = NamedSlots.build(type: ResourceNameIndex.persons, count: alive.count, names: gameData.snapshot?.names) { index in
            grudge.indices.contains(index) && grudge[index] != 0
        }
        .filter { slot in
            guard NamedSlots.matches(slot, query: query) else { return false }
            return !onlyChanged || isChanged(slot.index)
        }

        return VStack(spacing: 0) {
            ListFilterBar(searchText: $searchText, onlyChanged: $onlyChanged, onlyChangedLabel: "Gone or holding a grudge")
                .padding()

            Divider()

            List {
                Section {
                    ForEach(slots) { slot in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(slot.title)
                                    .lineLimit(1)

                                Text([slot.note, "ID \(slot.id)"].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Toggle("Active", isOn: int16Binding(alive, slot.index) { try pilotFile.setPersonAlive($0, at: slot.index) })
                                .toggleStyle(.checkbox)

                            Toggle("Grudge", isOn: int16Binding(grudge, slot.index) { try pilotFile.setPersonGrudge($0, at: slot.index) })
                                .toggleStyle(.checkbox)
                        }
                    }
                } header: {
                    Text("\(slots.count) characters")
                } footer: {
                    Text("Active: the character can still appear. Grudge: they're hostile to you. A character killed in the story shows as inactive.")
                }
            }
        }
        .editErrorAlert($errorMessage)
    }

    private func int16Binding(_ values: [Int16], _ index: Int, commit: @escaping (Int16) throws -> Void) -> Binding<Bool> {
        Binding(
            get: { values.indices.contains(index) && values[index] != 0 },
            set: { isOn in
                do {
                    try commit(isOn ? 1 : 0)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        )
    }
}

// Everything else that lives in the pilot's copy of the universe: ranks,
// timed events, disasters, junk cargo, and price swings.
struct UniversePane: View {
    @ObservedObject var pilotFile: PilotFile

    @EnvironmentObject private var gameData: GameDataStore

    @State private var errorMessage: String?
    @State private var showAllEvents = false

    var body: some View {
        let bytes: Data = pilotFile.workingBytes
        let names: ResourceNameIndex? = gameData.snapshot?.names

        // List, not Form: a grouped Form builds every row up front, and this
        // page has over a hundred. List only builds the rows on screen.
        List {
            ranksSection(bytes: bytes, names: names)
            eventsSection(bytes: bytes, names: names)
            disastersSection(bytes: bytes, names: names)
            junkSection(bytes: bytes, names: names)
            pricesSection(bytes: bytes)

            Section("Other") {
                Toggle("Intro screen already shown", isOn: Binding(
                    get: { PilotUniverseState.decodeSeenIntroScreen(from: pilotFile.workingBytes) },
                    set: { isOn in
                        perform {
                            try pilotFile.setSeenIntroScreen(isOn)
                        }
                    }
                ))
            }
        }
        .editErrorAlert($errorMessage)
    }

    // MARK: - Ranks

    private func ranksSection(bytes: Data, names: ResourceNameIndex?) -> some View {
        let active: [Int16] = PilotUniverseState.decodeRankActive(from: bytes)
        let slots: [NamedSlot] = NamedSlots.build(type: ResourceNameIndex.ranks, count: active.count, names: names) { index in
            active[index] != 0
        }

        return Section {
            if slots.isEmpty {
                Text("No ranks in the loaded game data.")
                    .foregroundStyle(.secondary)
            }

            ForEach(slots) { slot in
                Toggle(isOn: Binding(
                    get: { active.indices.contains(slot.index) && active[slot.index] != 0 },
                    set: { isOn in
                        perform {
                            try pilotFile.setRankActive(isOn ? 1 : 0, at: slot.index)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(slot.title)
                        Text([slot.note, "ID \(slot.id)"].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // Checkbox, not the Form's default switch: 31 switches made
                // this page slow to open.
                .toggleStyle(.checkbox)
            }
        } header: {
            Text("Ranks")
        } footer: {
            Text("Ranks are titles and standing with governments, usually granted by missions.")
        }
    }

    // MARK: - Timed events

    private func eventsSection(bytes: Data, names: ResourceNameIndex?) -> some View {
        let duration: [Int16] = PilotUniverseState.decodeCronDuration(from: bytes)
        let holdOff: [Int16] = PilotUniverseState.decodeCronHoldOff(from: bytes)
        // -1/-1 is the idle state (111 of 125 events in a real save), so
        // only other values count as running or recently run.
        let idleValue: Int16 = -1
        let isRunning: (Int) -> Bool = { index in
            (duration.indices.contains(index) && duration[index] != idleValue) || (holdOff.indices.contains(index) && holdOff[index] != idleValue)
        }
        let slots: [NamedSlot] = NamedSlots.build(type: ResourceNameIndex.crons, count: duration.count, names: names, isNonDefault: isRunning)
            .filter { showAllEvents || isRunning($0.index) }

        return Section {
            Toggle("Show all timed events", isOn: $showAllEvents)

            if slots.isEmpty {
                Text("No timed events are running.")
                    .foregroundStyle(.secondary)
            }

            ForEach(slots) { slot in
                HStack {
                    Text(slot.title)
                        .lineLimit(1)

                    Spacer()

                    Text("Days left")
                        .foregroundStyle(.secondary)

                    IntegerField(value: Int(duration.indices.contains(slot.index) ? duration[slot.index] : 0), range: Int(Int16.min)...Int(Int16.max), commit: { newValue in
                        try pilotFile.setCronDuration(Int16(newValue), at: slot.index)
                    }, onError: report, width: 60)

                    Text("Wait")
                        .foregroundStyle(.secondary)

                    IntegerField(value: Int(holdOff.indices.contains(slot.index) ? holdOff[slot.index] : 0), range: Int(Int16.min)...Int(Int16.max), commit: { newValue in
                        try pilotFile.setCronHoldOff(Int16(newValue), at: slot.index)
                    }, onError: report, width: 60)
                }
            }
        } header: {
            Text("Timed Events")
        } footer: {
            Text("Timed events run things like news, wars, and story beats on a schedule. \"Wait\" is the pause before the event can run again.")
        }
    }

    // MARK: - Disasters

    private func disastersSection(bytes: Data, names: ResourceNameIndex?) -> some View {
        let time: [Int16] = PilotUniverseState.decodeDisasterTime(from: bytes)
        let slots: [NamedSlot] = NamedSlots.build(type: ResourceNameIndex.disasters, count: time.count, names: names) { index in
            time[index] > 0
        }

        return Section {
            if slots.isEmpty {
                Text("No disasters in the loaded game data.")
                    .foregroundStyle(.secondary)
            }

            ForEach(slots) { slot in
                LabeledContent(slot.title) {
                    IntegerField(value: Int(time.indices.contains(slot.index) ? time[slot.index] : 0), range: Int(Int16.min)...Int(Int16.max), commit: { newValue in
                        try pilotFile.setDisasterTime(Int16(newValue), at: slot.index)
                    }, onError: report, width: 70)
                }
            }
        } header: {
            Text("Disasters (days remaining)")
        } footer: {
            Text("Disasters are plagues, strikes, and similar events that change prices on a planet. Set to 0 to end one.")
        }
    }

    // MARK: - Junk cargo

    private func junkSection(bytes: Data, names: ResourceNameIndex?) -> some View {
        let quantity: [Int16] = PilotUniverseState.decodeJunkQty(from: bytes)
        let slots: [NamedSlot] = NamedSlots.build(type: ResourceNameIndex.junk, count: quantity.count, names: names) { index in
            quantity[index] != 0
        }

        return Section {
            if slots.isEmpty {
                Text("No special cargo types in the loaded game data.")
                    .foregroundStyle(.secondary)
            }

            ForEach(slots) { slot in
                LabeledContent(slot.title) {
                    IntegerField(value: Int(quantity.indices.contains(slot.index) ? quantity[slot.index] : 0), range: 0...Int(Int16.max), commit: { newValue in
                        try pilotFile.setJunkQty(Int16(newValue), at: slot.index)
                    }, onError: report, width: 70)
                }
            }
        } header: {
            Text("Special Cargo (tons aboard)")
        } footer: {
            Text("Cargo you pick up from asteroids and wrecks, separate from ordinary trade goods.")
        }
    }

    // MARK: - Prices

    private func pricesSection(bytes: Data) -> some View {
        let flux: [Int16] = PilotUniverseState.decodePriceFlux(from: bytes)

        return Section {
            ForEach(flux.indices, id: \.self) { index in
                LabeledContent("Price swing \(index + 1)") {
                    IntegerField(value: Int(flux[index]), range: Int(Int16.min)...Int(Int16.max), commit: { newValue in
                        try pilotFile.setPriceFlux(Int16(newValue), at: index)
                    }, onError: report, width: 70)
                }
            }
        } header: {
            Text("Galaxy-wide Price Swings")
        } footer: {
            Text("The game adjusts these on its own over time. Their exact meaning isn't documented, so change them only if you know why.")
        }
    }

    // MARK: - Helpers

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
