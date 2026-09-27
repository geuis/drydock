import SwiftUI

// Owned outfits, installed weapons, and ammunition, shown by name. The pilot
// file stores each as a count indexed by (resource ID - 128).
struct OutfitsWeaponsPane: View {
    @ObservedObject var pilotFile: PilotFile

    @EnvironmentObject private var gameData: GameDataStore

    @State private var errorMessage: String?
    @State private var showingOutfitPicker = false
    @State private var showingWeaponPicker = false
    @State private var showingStockConfirmation = false

    var body: some View {
        Form {
            outfitsSection
            weaponsSection
            stockSection
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingOutfitPicker) {
            CatalogPickerSheet(title: "Add Outfit", items: outfitPickerItems) { outfitID in
                perform {
                    try pilotFile.setItemCount(1, at: outfitID - 128)
                }
            }
        }
        .sheet(isPresented: $showingWeaponPicker) {
            CatalogPickerSheet(title: "Add Weapon", items: weaponPickerItems) { weaponID in
                perform {
                    try pilotFile.setWeapCount(1, at: weaponID - 128)
                }
            }
        }
        .confirmationDialog(
            "Add the standard loadout for \(currentShipTitle)?",
            isPresented: $showingStockConfirmation,
            titleVisibility: .visible
        ) {
            Button("Add Loadout") {
                installStockLoadout()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This adds the weapons, ammunition, and outfits the ship comes with when bought. Items you already own are kept.")
        }
        .editErrorAlert($errorMessage)
    }

    // MARK: - Outfits

    private var outfitsSection: some View {
        let counts: [Int16] = PilotInventory.decodeItemCount(from: pilotFile.workingBytes)
        let ownedIndices: [Int] = counts.indices.filter { counts[$0] > 0 }

        return Section {
            if ownedIndices.isEmpty {
                Text("No outfits owned.")
                    .foregroundStyle(.secondary)
            }

            ForEach(ownedIndices, id: \.self) { index in
                let outfitID: Int = index + 128
                let outfit: OutfitDefinition? = outfitsByID[outfitID]

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outfit.map { GameName($0.name).full } ?? "Outfit \(outfitID)")

                        Text(outfitDetail(outfit, id: outfitID))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    IntegerField(value: Int(counts[index]), range: 0...Int(Int16.max), commit: { newValue in
                        try pilotFile.setItemCount(Int16(newValue), at: index)
                    }, onError: report, width: 70)

                    removeButton {
                        try pilotFile.setItemCount(0, at: index)
                    }
                }
            }

            Button {
                showingOutfitPicker = true
            } label: {
                Label("Add Outfit…", systemImage: "plus")
            }
            .disabled(gameData.snapshot?.outfits.isEmpty ?? true)
        } header: {
            Text("Outfits")
        } footer: {
            Text("Includes items with no visible effect that plugins and missions use as keys or markers.")
        }
    }

    private func outfitDetail(_ outfit: OutfitDefinition?, id: Int) -> String {
        guard let outfit else { return "ID \(id) · not in the loaded game data" }

        var parts: [String] = [OutfitDefinition.modTypeDescription(for: outfit.modType)]

        if outfit.mass > 0 {
            parts.append("\(outfit.mass) \(outfit.mass == 1 ? "ton" : "tons") each")
        }

        parts.append("ID \(id)")
        return parts.joined(separator: " · ")
    }

    // MARK: - Weapons

    private var weaponsSection: some View {
        let counts: [Int16] = PilotInventory.decodeWeapCount(from: pilotFile.workingBytes)
        let ammo: [Int16] = PilotInventory.decodeAmmo(from: pilotFile.workingBytes)
        let shownIndices: [Int] = counts.indices.filter { counts[$0] > 0 || (ammo.indices.contains($0) && ammo[$0] > 0) }

        return Section {
            if shownIndices.isEmpty {
                Text("No weapons installed.")
                    .foregroundStyle(.secondary)
            }

            ForEach(shownIndices, id: \.self) { index in
                let weaponID: Int = index + 128
                let weapon: WeaponDefinition? = weaponsByID[weaponID]

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weapon.map { GameName($0.name).full } ?? "Weapon \(weaponID)")

                        Text(weaponDetail(weapon, id: weaponID))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("Count")
                        .foregroundStyle(.secondary)

                    IntegerField(value: Int(counts[index]), range: 0...Int(Int16.max), commit: { newValue in
                        try pilotFile.setWeapCount(Int16(newValue), at: index)
                    }, onError: report, width: 60)

                    Text("Ammo")
                        .foregroundStyle(.secondary)

                    IntegerField(value: ammo.indices.contains(index) ? Int(ammo[index]) : 0, range: 0...Int(Int16.max), commit: { newValue in
                        try pilotFile.setAmmo(Int16(newValue), at: index)
                    }, onError: report, width: 70)

                    removeButton {
                        try pilotFile.setWeapCount(0, at: index)
                        try pilotFile.setAmmo(0, at: index)
                    }
                }
            }

            Button {
                showingWeaponPicker = true
            } label: {
                Label("Add Weapon…", systemImage: "plus")
            }
            .disabled(gameData.snapshot?.weapons.isEmpty ?? true)
        } header: {
            Text("Weapons")
        } footer: {
            Text("Ammo is stored per weapon type. It's kept even when the launcher count is zero.")
        }
    }

    private func weaponDetail(_ weapon: WeaponDefinition?, id: Int) -> String {
        guard let weapon else { return "ID \(id) · not in the loaded game data" }
        return "\(WeaponDefinition.guidanceDescription(for: weapon.guidance)) · ID \(id)"
    }

    // MARK: - Stock loadout

    private var stockSection: some View {
        Section {
            Button("Add Standard Loadout for \(currentShipTitle)…") {
                showingStockConfirmation = true
            }
            .disabled(currentShip == nil)
        } header: {
            Text("Ship Loadout")
        } footer: {
            Text("Useful after changing ship type on the Pilot & Ship page, since changing type alone doesn't add the new ship's weapons.")
        }
    }

    // Mirrors what buying the ship gives you: its default weapon slots
    // (with ammo) and default outfit slots, added on top of what's owned.
    private func installStockLoadout() {
        guard let ship = currentShip else { return }

        perform {
            let weaponCounts: [Int16] = PilotInventory.decodeWeapCount(from: pilotFile.workingBytes)
            let ammoCounts: [Int16] = PilotInventory.decodeAmmo(from: pilotFile.workingBytes)

            for slot in ship.weapType.indices {
                let weaponID: Int = Int(ship.weapType[slot])
                let count: Int16 = slot < ship.weapCount.count ? ship.weapCount[slot] : 0
                let ammoLoad: Int16 = slot < ship.ammoLoad.count ? ship.ammoLoad[slot] : 0
                let index: Int = weaponID - 128

                guard weaponCounts.indices.contains(index), count > 0 else { continue }

                try pilotFile.setWeapCount(clampedSum(weaponCounts[index], count), at: index)

                if ammoLoad > 0, ammoCounts.indices.contains(index) {
                    try pilotFile.setAmmo(clampedSum(ammoCounts[index], ammoLoad), at: index)
                }
            }

            let itemGroups: [([Int16], [Int16])] = [
                (ship.defaultItems, ship.itemCount),
                (ship.defaultItems2, ship.itemCount2)
            ]

            for (itemIDs, itemCounts) in itemGroups {
                for slot in itemIDs.indices {
                    let index: Int = Int(itemIDs[slot]) - 128
                    let count: Int16 = slot < itemCounts.count ? itemCounts[slot] : 0
                    let owned: [Int16] = PilotInventory.decodeItemCount(from: pilotFile.workingBytes)

                    guard owned.indices.contains(index), count > 0 else { continue }

                    try pilotFile.setItemCount(clampedSum(owned[index], count), at: index)
                }
            }
        }
    }

    private func clampedSum(_ first: Int16, _ second: Int16) -> Int16 {
        let total: Int = Int(max(first, 0)) + Int(second)
        return Int16(min(total, Int(Int16.max)))
    }

    // MARK: - Lookups

    private var outfitsByID: [Int: OutfitDefinition] {
        gameData.snapshot?.outfitsByID ?? [:]
    }

    private var weaponsByID: [Int: WeaponDefinition] {
        gameData.snapshot?.weaponsByID ?? [:]
    }

    private var currentShip: ShipDefinition? {
        let shipID: Int = Int(pilotFile.shipClassIndex) + 128
        return gameData.snapshot?.shipsByID[shipID]
    }

    private var currentShipTitle: String {
        currentShip.map { GameName($0.name).title } ?? "Current Ship"
    }

    private var outfitPickerItems: [PickerItem] {
        (gameData.snapshot?.outfits ?? [])
            .filter { (128..<(128 + 512)).contains($0.id) }
            .map { outfit in
                let name: GameName = GameName(outfit.name)
                let detail: [String] = [name.note, OutfitDefinition.modTypeDescription(for: outfit.modType), "ID \(outfit.id)"].compactMap { $0 }
                return PickerItem(id: outfit.id, title: name.title, detail: detail.joined(separator: " · "))
            }
    }

    private var weaponPickerItems: [PickerItem] {
        (gameData.snapshot?.weapons ?? [])
            .filter { (128..<(128 + 256)).contains($0.id) }
            .map { weapon in
                let name: GameName = GameName(weapon.name)
                let detail: [String] = [name.note, WeaponDefinition.guidanceDescription(for: weapon.guidance), "ID \(weapon.id)"].compactMap { $0 }
                return PickerItem(id: weapon.id, title: name.title, detail: detail.joined(separator: " · "))
            }
    }

    // MARK: - Helpers

    private func removeButton(_ action: @escaping () throws -> Void) -> some View {
        Button(role: .destructive) {
            perform(action)
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help("Remove")
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
