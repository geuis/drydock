import SwiftUI

// Escort and fighter slots. escortClass stores (ship ID - 128) for a
// captured escort and 1000 + (ship ID - 128) for a hired one; -1 is empty.
// fighterClass stores (ship ID - 128) or -1.
struct EscortsPane: View {
    @ObservedObject var pilotFile: PilotFile

    @EnvironmentObject private var gameData: GameDataStore

    @State private var errorMessage: String?
    @State private var addingEscortKind: EscortKind?
    @State private var showingFighterPicker = false

    private enum EscortKind: String, Identifiable {
        case captured
        case hired

        var id: String { rawValue }
    }

    private static let hiredOffset: Int16 = 1000

    private static let orderChoices: [(value: Int16, label: String)] = [
        (0, "Formation"),
        (1, "Defend"),
        (2, "Attack"),
        (3, "Return to Hangar"),
        (4, "Hold Position")
    ]

    private static let orderCategories: [String] = ["Fighters", "Medium Ships", "Warships", "Freighters"]

    var body: some View {
        Form {
            escortsSection
            fightersSection
            ordersSection
        }
        .formStyle(.grouped)
        .sheet(item: $addingEscortKind) { kind in
            CatalogPickerSheet(title: kind == .hired ? "Add Hired Escort" : "Add Captured Escort", items: shipPickerItems) { shipID in
                perform {
                    try addEscort(shipID: shipID, hired: kind == .hired)
                }
            }
        }
        .sheet(isPresented: $showingFighterPicker) {
            CatalogPickerSheet(title: "Add Deployed Fighter", items: shipPickerItems) { shipID in
                perform {
                    try addFighter(shipID: shipID)
                }
            }
        }
        .editErrorAlert($errorMessage)
    }

    // MARK: - Escorts

    private var escortsSection: some View {
        let classes: [Int16] = PilotEscorts.decodeEscortClass(from: pilotFile.workingBytes)
        let upgrades: [Int16] = PilotEscorts.decodeEscortUpgrade(from: pilotFile.workingBytes)
        let sales: [Int16] = PilotEscorts.decodeEscortSale(from: pilotFile.workingBytes)
        let voices: [Int16] = PilotEscorts.decodeEscortVoiceMode(from: pilotFile.workingBytes)
        let usedSlots: [Int] = classes.indices.filter { classes[$0] >= 0 }

        return Section {
            if usedSlots.isEmpty {
                Text("No escorts.")
                    .foregroundStyle(.secondary)
            }

            ForEach(usedSlots, id: \.self) { slot in
                let raw: Int16 = classes[slot]
                let isHired: Bool = raw >= Self.hiredOffset
                let shipIndex: Int16 = isHired ? raw - Self.hiredOffset : raw

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(shipTitle(index: shipIndex))
                            .font(.headline)

                        Spacer()

                        Picker("Status", selection: Binding(
                            get: { isHired },
                            set: { hired in
                                perform {
                                    try pilotFile.setEscortClass(hired ? shipIndex + Self.hiredOffset : shipIndex, at: slot)
                                }
                            }
                        )) {
                            Text("Captured").tag(false)
                            Text("Hired").tag(true)
                        }
                        .labelsHidden()
                        .fixedSize()

                        Button(role: .destructive) {
                            perform {
                                try pilotFile.setEscortClass(-1, at: slot)
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove escort")
                    }

                    // fixedSize keeps the grouped Form from squeezing the
                    // checkbox labels into word-wrapped columns.
                    HStack(spacing: 16) {
                        Toggle("Upgrade scheduled", isOn: flagBinding(upgrades, slot: slot) { try pilotFile.setEscortUpgrade($0, at: slot) })
                            .fixedSize()
                        Toggle("Sale scheduled", isOn: flagBinding(sales, slot: slot) { try pilotFile.setEscortSale($0, at: slot) })
                            .fixedSize()

                        Spacer()

                        Text("Voice")
                            .foregroundStyle(.secondary)

                        Picker("Voice", selection: Binding(
                            get: { voices.indices.contains(slot) ? voices[slot] : -1 },
                            set: { newValue in
                                perform {
                                    try pilotFile.setEscortVoiceMode(newValue, at: slot)
                                }
                            }
                        )) {
                            Text("Default").tag(Int16(-1))
                            Text("Even sounds").tag(Int16(0))
                            Text("Odd sounds").tag(Int16(1))
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .toggleStyle(.checkbox)
                    .font(.callout)
                }
                .padding(.vertical, 2)
            }

            HStack {
                Button {
                    addingEscortKind = .hired
                } label: {
                    Label("Add Hired Escort…", systemImage: "plus")
                }

                Button {
                    addingEscortKind = .captured
                } label: {
                    Label("Add Captured Escort…", systemImage: "plus")
                }
            }
            .disabled(hasNoShips || usedSlots.count >= classes.count)
        } header: {
            Text("Escorts")
        } footer: {
            Text("The game normally limits how many escorts you can have. Going over that limit can make it unstable.")
        }
    }

    private func flagBinding(_ values: [Int16], slot: Int, commit: @escaping (Int16) throws -> Void) -> Binding<Bool> {
        Binding(
            get: { values.indices.contains(slot) && values[slot] > 0 },
            set: { isOn in
                perform {
                    try commit(isOn ? 1 : 0)
                }
            }
        )
    }

    private func addEscort(shipID: Int, hired: Bool) throws {
        let classes: [Int16] = PilotEscorts.decodeEscortClass(from: pilotFile.workingBytes)

        guard let freeSlot = classes.firstIndex(where: { $0 < 0 }) else {
            throw WorkspaceError.invalidValue("All escort slots are full.")
        }

        let shipIndex: Int16 = Int16(shipID - 128)
        try pilotFile.setEscortClass(hired ? shipIndex + Self.hiredOffset : shipIndex, at: freeSlot)
    }

    // MARK: - Fighters

    private var fightersSection: some View {
        let fighters: [Int16] = PilotEscorts.decodeFighterClass(from: pilotFile.workingBytes)
        let usedSlots: [Int] = fighters.indices.filter { fighters[$0] >= 0 }

        return Section("Deployed Fighters") {
            if usedSlots.isEmpty {
                Text("No fighters deployed.")
                    .foregroundStyle(.secondary)
            }

            ForEach(usedSlots, id: \.self) { slot in
                HStack {
                    Text(shipTitle(index: fighters[slot]))

                    Spacer()

                    Button(role: .destructive) {
                        perform {
                            try pilotFile.setFighterClass(-1, at: slot)
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove fighter")
                }
            }

            Button {
                showingFighterPicker = true
            } label: {
                Label("Add Fighter…", systemImage: "plus")
            }
            .disabled(hasNoShips || usedSlots.count >= fighters.count)
        }
    }

    private func addFighter(shipID: Int) throws {
        let fighters: [Int16] = PilotEscorts.decodeFighterClass(from: pilotFile.workingBytes)

        guard let freeSlot = fighters.firstIndex(where: { $0 < 0 }) else {
            throw WorkspaceError.invalidValue("All fighter slots are full.")
        }

        try pilotFile.setFighterClass(Int16(shipID - 128), at: freeSlot)
    }

    // MARK: - Orders

    private var ordersSection: some View {
        let orders: [Int16] = PilotUniverseState.decodeEscortOrders(from: pilotFile.workingBytes)

        return Section("Standing Orders") {
            ForEach(Self.orderCategories.indices, id: \.self) { index in
                Picker(Self.orderCategories[index], selection: Binding(
                    get: { orders.indices.contains(index) ? orders[index] : 0 },
                    set: { newValue in
                        perform {
                            try pilotFile.setEscortOrder(newValue, at: index)
                        }
                    }
                )) {
                    ForEach(Self.orderChoices, id: \.value) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
            }
        }
    }

    // MARK: - Lookups

    private func shipTitle(index: Int16) -> String {
        let shipID: Int = Int(index) + 128

        guard let ship = gameData.snapshot?.shipsByID[shipID] else {
            return "Ship \(shipID)"
        }

        return GameName(ship.name).full
    }

    // Cheap check for the Add buttons; building shipPickerItems just to
    // test emptiness would sort every ship on every redraw.
    private var hasNoShips: Bool {
        gameData.snapshot?.ships.isEmpty ?? true
    }

    private var shipPickerItems: [PickerItem] {
        (gameData.snapshot?.ships ?? [])
            .map { ship in
                let name: GameName = GameName(ship.name)
                return PickerItem(id: ship.id, title: name.title, detail: [name.note, "ID \(ship.id)"].compactMap { $0 }.joined(separator: " · "))
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
