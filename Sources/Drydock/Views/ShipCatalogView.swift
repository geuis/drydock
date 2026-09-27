import SwiftUI

// Standalone browsing view for decoded shïp resources - lists every ship
// class found in the game's data files with its key stats, sortable by
// name/cost/tech level. Not yet wired into the app's main navigation (see
// ShipDefinition.swift's task notes): a future pass will combine this with
// an outfit/weapon catalog view under one unified "item catalog" screen.
public struct ShipCatalogView: View {
    private enum SortField: String, CaseIterable, Identifiable {
        case name = "Name"
        case cost = "Cost"
        case techLevel = "Tech Level"

        var id: String { rawValue }
    }

    @EnvironmentObject private var gameData: GameDataStore
    @State private var sortField: SortField = .name
    @State private var sortAscending = true
    @State private var selection: ShipDefinition.ID?

    public init() {}

    private var ships: [ShipDefinition] { gameData.snapshot?.ships ?? [] }

    public var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = gameData.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if gameData.isLoading {
                ProgressView("Loading ships\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if ships.isEmpty {
                Text("No ships found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .navigationTitle("Ship Catalog")
        // Surfaces the fields decoded from offset 100 onward (Availability
        // through MovieFile - see ShipDefinition.swift) that don't fit in
        // the Table's columns above. Opens automatically when a row is
        // selected, matching how Outfit/WeaponCatalogView show their
        // detail panels.
        .inspector(isPresented: inspectorPresented) {
            if let selectedShip {
                ShipDetailView(ship: selectedShip)
            } else {
                Text("Select a ship")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // Selected ship for the detail inspector below - kept separate from
    // the raw `selection` ID so the inspector can gracefully show nothing
    // if the selected ship somehow isn't in the current `ships` array.
    private var selectedShip: ShipDefinition? {
        guard let selection else { return nil }
        return ships.first { $0.id == selection }
    }

    // Drives the inspector purely off whether a row is selected, rather
    // than a separate piece of @State - selecting a row opens it,
    // deselecting (or the inspector's own close control) clears it.
    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: { isPresented in if !isPresented { selection = nil } }
        )
    }

    private var table: some View {
        Table(sortedShips, selection: $selection) {
            TableColumn("Name") { ship in
                Text(ship.name)
            }
            TableColumn("Tech") { ship in
                Text("\(ship.techLevel)")
            }
            TableColumn("Cost") { ship in
                Text(formattedCredits(ship.cost))
            }
            TableColumn("Holds") { ship in
                Text("\(ship.holds)")
            }
            TableColumn("Shield") { ship in
                Text("\(ship.shield)")
            }
            TableColumn("Armor") { ship in
                Text("\(ship.armor)")
            }
            TableColumn("Speed") { ship in
                Text("\(ship.speed)")
            }
            TableColumn("Accel") { ship in
                Text("\(ship.accel)")
            }
            TableColumn("Fuel") { ship in
                Text("\(ship.fuel)")
            }
            TableColumn("Crew") { ship in
                Text("\(ship.crew)")
            }
        }
        .safeAreaInset(edge: .top) {
            sortControls
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
    }

    private var sortControls: some View {
        HStack {
            Text("Sort by")
                .foregroundStyle(.secondary)

            Picker("Sort by", selection: $sortField) {
                ForEach(SortField.allCases) { field in
                    Text(field.rawValue).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 160)

            Button {
                sortAscending.toggle()
            } label: {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("\(ships.count) ships")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sortedShips: [ShipDefinition] {
        let comparator: (ShipDefinition, ShipDefinition) -> Bool
        switch sortField {
        case .name:
            comparator = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .cost:
            comparator = { $0.cost < $1.cost }
        case .techLevel:
            comparator = { $0.techLevel < $1.techLevel }
        }

        let sorted = ships.sorted(by: comparator)
        return sortAscending ? sorted : sorted.reversed()
    }

    private func formattedCredits(_ cost: Int32) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: cost), number: .decimal)
    }

}

// Detail panel for the fields decoded from offset 100 onward (see
// ShipDefinition.swift's file doc comment for how these were validated) -
// the Table above only has room for the core performance/cost columns, so
// anything decoded past Flags2 (names, subtitle, gating expressions,
// escort upgrade info, etc.) is surfaced here instead.
private struct ShipDetailView: View {
    let ship: ShipDefinition

    var body: some View {
        Form {
            Section("Names") {
                LabeledContent("Short Name", value: ship.shortName.isEmpty ? "(none)" : ship.shortName)
                LabeledContent("Comm Name", value: ship.commName.isEmpty ? "(none)" : ship.commName)
                LabeledContent("Long Name", value: ship.longName.isEmpty ? "(none)" : ship.longName)
                LabeledContent("Subtitle", value: ship.subtitle.isEmpty ? "(none)" : ship.subtitle)
                LabeledContent("Movie File", value: ship.movieFile.isEmpty ? "(none)" : ship.movieFile)
            }

            if !ship.availability.isEmpty || !ship.appearOn.isEmpty || !ship.onPurchase.isEmpty
                || !ship.onCapture.isEmpty || !ship.onRetire.isEmpty {
                Section("Control Bit Expressions") {
                    if !ship.availability.isEmpty {
                        LabeledContent("Availability", value: ship.availability)
                    }
                    if !ship.appearOn.isEmpty {
                        LabeledContent("Appear On", value: ship.appearOn)
                    }
                    if !ship.onPurchase.isEmpty {
                        LabeledContent("On Purchase", value: ship.onPurchase)
                    }
                    if !ship.onCapture.isEmpty {
                        LabeledContent("On Capture", value: ship.onCapture)
                    }
                    if !ship.onRetire.isEmpty {
                        LabeledContent("On Retire", value: ship.onRetire)
                    }
                }
            }

            Section("Escort Upgrade") {
                LabeledContent("Escort Type", value: ShipDetailView.escortTypeDescription(for: ship.escortType))
                if ship.upgradeTo > 0 {
                    LabeledContent("Upgrades To Ship ID", value: "\(ship.upgradeTo)")
                    LabeledContent("Upgrade Cost", value: "\(ship.escUpgrdCost) credits")
                }
                LabeledContent("Sell Value", value: ship.escSellValue > 0 ? "\(ship.escSellValue) credits" : "10% of cost (default)")
                LabeledContent("Flags3", value: "0x" + String(ship.flags3, radix: 16))
            }

            Section("Ionization") {
                LabeledContent("Deionize Rate", value: "\(ship.deionize)")
                LabeledContent("Ionize Max", value: "\(ship.ionizeMax)")
            }

            if ship.keyCarried != 0 {
                Section("Key Carried") {
                    LabeledContent("Key Carried Ship ID", value: "\(ship.keyCarried)")
                }
            }

            if ship.defaultItems2.contains(where: { $0 > 0 }) {
                Section("Second Default Equipment") {
                    ForEach(ship.defaultItems2.indices, id: \.self) { slot in
                        let item = ship.defaultItems2[slot]
                        if item > 0 {
                            LabeledContent("Item \(slot)", value: "outfit \(item) x\(ship.itemCount2[slot])")
                        }
                    }
                }
            }

            if ship.contribute1 != 0 || ship.contribute2 != 0 || ship.require1 != 0 || ship.require2 != 0 {
                Section("Contribute / Require") {
                    if ship.contribute1 != 0 || ship.contribute2 != 0 {
                        LabeledContent("Contribute", value: "0x" + String(UInt16(bitPattern: ship.contribute1), radix: 16) + " " + String(UInt16(bitPattern: ship.contribute2), radix: 16))
                    }
                    if ship.require1 != 0 || ship.require2 != 0 {
                        LabeledContent("Require", value: "0x" + String(UInt16(bitPattern: ship.require1), radix: 16) + " " + String(UInt16(bitPattern: ship.require2), radix: 16))
                    }
                }
            }

            Section("Purchase / Hire Odds") {
                LabeledContent("Buy Random", value: "\(ship.buyRandom)%")
                LabeledContent("Hire Random", value: "\(ship.hireRandom)%")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(ship.shortName.isEmpty ? ship.name : ship.shortName)
    }

    private static func escortTypeDescription(for escortType: Int16) -> String {
        switch escortType {
        case -1: return "Auto"
        case 0: return "Fighter"
        case 1: return "Medium Ship"
        case 2: return "Warship"
        case 3: return "Freighter"
        default: return "Unknown (\(escortType))"
        }
    }
}
