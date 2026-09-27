import SwiftUI

// Scalar fields still live in FieldSchema.json. These helpers let the
// workspace read and write them by id without every pane repeating the
// lookup and the PilotFieldValue unwrapping.
extension PilotFile {
    func schemaInt(_ id: String, in schema: FieldSchema) -> Int? {
        guard let field = schema.fields.first(where: { $0.id == id }) else { return nil }

        if case .int(let value)? = value(for: field) {
            return value
        }

        return nil
    }

    func setSchemaInt(_ id: String, to newValue: Int, in schema: FieldSchema) throws {
        guard let field = schema.fields.first(where: { $0.id == id }) else {
            throw WorkspaceError.missingField(id)
        }

        try setValue(.int(newValue), for: field)
    }
}

struct OverviewPane: View {
    @ObservedObject var pilotFile: PilotFile

    @EnvironmentObject private var schema: FieldSchema
    @EnvironmentObject private var gameData: GameDataStore

    @State private var errorMessage: String?
    @State private var showingShipPicker = false
    @State private var showingLocationPicker = false

    var body: some View {
        Form {
            pilotSection
            shipSection
            locationSection
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingShipPicker) {
            CatalogPickerSheet(title: "Choose Ship Type", items: shipPickerItems) { shipID in
                perform {
                    try pilotFile.setShipClassIndex(Int16(shipID - 128))
                }
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            CatalogPickerSheet(title: "Choose Planet or Station", items: stellarPickerItems) { stellarID in
                perform {
                    try pilotFile.setSchemaInt("lastStellar", to: stellarID - 128, in: schema)
                }
            }
        }
        .editErrorAlert($errorMessage)
    }

    // MARK: - Sections

    private var pilotSection: some View {
        Section("Pilot") {
            LabeledContent("Pilot File") {
                Text(pilotFile.url.lastPathComponent)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Nickname") {
                TextCommitField(value: pilotFile.nickname, placeholder: "Nickname", commit: { newValue in
                    try pilotFile.setNickname(newValue)
                }, onError: report)
            }

            Picker("Gender", selection: Binding(
                get: { pilotFile.isMale },
                set: { isMale in
                    perform {
                        try pilotFile.setIsMale(isMale)
                    }
                }
            )) {
                Text("Male").tag(true)
                Text("Female").tag(false)
            }

            Toggle("Strict Play", isOn: Binding(
                get: { pilotFile.strictPlay },
                set: { isOn in
                    perform {
                        try pilotFile.setStrictPlay(isOn)
                    }
                }
            ))

            LabeledContent("Credits") {
                IntegerField(value: Int(pilotFile.credits), range: 0...Int(Int32.max), commit: { newValue in
                    try pilotFile.setSchemaInt("cash", to: newValue, in: schema)
                }, onError: report, width: 140)
            }

            LabeledContent("Combat Rating") {
                IntegerField(value: Int(pilotFile.combatRating), range: 0...Int(Int32.max), commit: { newValue in
                    try pilotFile.setSchemaInt("rating", to: newValue, in: schema)
                }, onError: report, width: 140)
            }
        }
    }

    private var shipSection: some View {
        Section {
            LabeledContent("Ship Type") {
                HStack {
                    Text(currentShipTitle)

                    Button("Change…") {
                        showingShipPicker = true
                    }
                    .disabled(ships.isEmpty)
                }
            }

            LabeledContent("Ship Name") {
                TextCommitField(value: pilotFile.shipName, placeholder: "Ship name", commit: { newValue in
                    try pilotFile.setShipName(newValue)
                }, onError: report)
            }

            LabeledContent("Fuel") {
                HStack {
                    IntegerField(value: pilotFile.schemaInt("fuel", in: schema) ?? 0, range: 0...Int(Int16.max), commit: { newValue in
                        try pilotFile.setSchemaInt("fuel", to: newValue, in: schema)
                    }, onError: report)

                    if let maxFuel = capacity?.fuelCapacity {
                        Text("of \(maxFuel) (100 per jump)")
                            .foregroundStyle(.secondary)

                        Button("Fill Tank") {
                            perform {
                                try pilotFile.setSchemaInt("fuel", to: Int(maxFuel), in: schema)
                            }
                        }
                    } else {
                        Text("100 per jump")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let capacity {
                capacityRows(capacity)
            }

            paintRow
        } header: {
            Text("Ship")
        } footer: {
            UnconfirmedFieldNote(fields: "Paint color")
        }
    }

    // Some missions aren't offered without free hold space, and outfits
    // like the Mass Retool quietly shrink the hold, so show the real
    // figures and where they come from.
    @ViewBuilder
    private func capacityRows(_ capacity: ShipCapacity) -> some View {
        LabeledContent("Cargo Space") {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(capacity.freeCargo) of \(capacity.cargoCapacity) tons free")

                Text(cargoBreakdown(capacity))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        LabeledContent("Free Mass") {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(capacity.freeMass) of \(capacity.totalMass) tons free")

                Text("Space left for outfits and weapons. Estimated from the ship's free mass, its stock equipment, and every owned outfit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func cargoBreakdown(_ capacity: ShipCapacity) -> String {
        var parts: [String] = ["Hold \(capacity.baseCargo)"]

        for adjustment in capacity.cargoAdjustments {
            let sign: String = adjustment.amount > 0 ? "+" : ""
            let copies: String = adjustment.count > 1 ? " x\(adjustment.count)" : ""
            parts.append("\(GameName(adjustment.outfitName).title)\(copies) \(sign)\(adjustment.amount)")
        }

        if capacity.tradeCargo > 0 {
            parts.append("\(capacity.tradeCargo) of goods aboard")
        }

        if capacity.missionCargo > 0 {
            parts.append("\(capacity.missionCargo) of mission cargo")
        }

        return parts.joined(separator: ", ")
    }

    private var paintRow: some View {
        let red: Int16 = PilotUniverseState.decodeShipColorRed(from: pilotFile.workingBytes)
        let green: Int16 = PilotUniverseState.decodeShipColorGreen(from: pilotFile.workingBytes)
        let blue: Int16 = PilotUniverseState.decodeShipColorBlue(from: pilotFile.workingBytes)

        return LabeledContent("Paint Color") {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: Double(red) / 32.0, green: Double(green) / 32.0, blue: Double(blue) / 32.0))
                    .frame(width: 28, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))

                colorChannel("R", value: red) { try pilotFile.setShipColorRed($0) }
                colorChannel("G", value: green) { try pilotFile.setShipColorGreen($0) }
                colorChannel("B", value: blue) { try pilotFile.setShipColorBlue($0) }
            }
        }
    }

    private func colorChannel(_ label: String, value: Int16, commit: @escaping (Int16) throws -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)

            IntegerField(value: Int(value), range: 0...32, commit: { newValue in
                try commit(Int16(newValue))
            }, onError: report, width: 48)
        }
        .help("0 to 32")
    }

    private var locationSection: some View {
        Section {
            LabeledContent("Last Planet or Station") {
                HStack {
                    Text(currentStellarTitle)

                    Button("Change…") {
                        showingLocationPicker = true
                    }
                    .disabled(gameData.snapshot?.names.entries(ofType: ResourceNameIndex.stellars).isEmpty ?? true)
                }
            }

            LabeledContent("Date (Month / Day / Year)") {
                HStack {
                    IntegerField(value: pilotFile.schemaInt("gameMonth", in: schema) ?? 1, range: 1...12, commit: { newValue in
                        try pilotFile.setSchemaInt("gameMonth", to: newValue, in: schema)
                    }, onError: report, width: 48)

                    IntegerField(value: pilotFile.schemaInt("gameDay", in: schema) ?? 1, range: 1...31, commit: { newValue in
                        try pilotFile.setSchemaInt("gameDay", to: newValue, in: schema)
                    }, onError: report, width: 48)

                    IntegerField(value: pilotFile.schemaInt("gameYear", in: schema) ?? 1, range: 0...Int(Int16.max), commit: { newValue in
                        try pilotFile.setSchemaInt("gameYear", to: newValue, in: schema)
                    }, onError: report, width: 70)
                }
            }

            LabeledContent("Date Prefix") {
                TextCommitField(value: PilotUniverseState.decodeDatePrefix(from: pilotFile.workingBytes), placeholder: "None", commit: { newValue in
                    try pilotFile.setDatePrefix(newValue)
                }, onError: report)
            }

            LabeledContent("Date Suffix") {
                TextCommitField(value: PilotUniverseState.decodeDateSuffix(from: pilotFile.workingBytes), placeholder: "None", commit: { newValue in
                    try pilotFile.setDateSuffix(newValue)
                }, onError: report)
            }
        } header: {
            Text("Location & Date")
        } footer: {
            UnconfirmedFieldNote(fields: "Last planet and date prefix/suffix")
        }
    }

    // MARK: - Lookups

    private var ships: [ShipDefinition] {
        gameData.snapshot?.ships ?? []
    }

    private var currentShip: ShipDefinition? {
        let shipID: Int = Int(pilotFile.shipClassIndex) + 128
        return gameData.snapshot?.shipsByID[shipID]
    }

    private var currentShipTitle: String {
        let shipID: Int = Int(pilotFile.shipClassIndex) + 128

        guard let currentShip else { return "Ship \(shipID)" }
        return "\(GameName(currentShip.name).full) (ID \(shipID))"
    }

    // Hold, tank, and outfit space with owned outfits counted. Using the
    // stock figures would make "Fill Tank" drain pilots who bought extra
    // tanks, and overstate the hold for pilots with mass expansions.
    private var capacity: ShipCapacity? {
        guard let currentShip, let outfitsByID = gameData.snapshot?.outfitsByID else { return nil }

        return ShipCapacity(ship: currentShip, outfitsByID: outfitsByID, pilotBytes: pilotFile.workingBytes)
    }

    private var shipPickerItems: [PickerItem] {
        ships
            .map { ship in
                let name: GameName = GameName(ship.name)
                return PickerItem(
                    id: ship.id,
                    title: name.title,
                    detail: [name.note, "ID \(ship.id)", "\(ship.cost) credits"].compactMap { $0 }.joined(separator: " · ")
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var stellarPickerItems: [PickerItem] {
        guard let names = gameData.snapshot?.names else { return [] }

        return names.entries(ofType: ResourceNameIndex.stellars).map { entry in
            let name: GameName = GameName(entry.name)
            return PickerItem(id: entry.id, title: name.title, detail: [name.note, "ID \(entry.id)"].compactMap { $0 }.joined(separator: " · "))
        }
    }

    private var currentStellarTitle: String {
        guard let index = pilotFile.schemaInt("lastStellar", in: schema) else { return "Unknown" }

        let stellarID: Int = index + 128

        if let name = gameData.snapshot?.names.name(type: ResourceNameIndex.stellars, id: stellarID) {
            return "\(GameName(name).full) (ID \(stellarID))"
        }

        return "Stellar \(stellarID)"
    }

    // MARK: - Error handling

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
