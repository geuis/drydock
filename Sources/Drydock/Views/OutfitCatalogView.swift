import SwiftUI

// Standalone browser for every decoded oütf (outfit/equipment) resource
// found in the configured Nova Files folder. Not wired into the main pilot
// editor navigation yet - see OutfitDefinition for what's decoded and what
// isn't.
public struct OutfitCatalogView: View {
    @EnvironmentObject private var gameData: GameDataStore
    @State private var selectedOutfitID: Int?

    public init() {}

    private var outfits: [OutfitDefinition] { gameData.snapshot?.outfits ?? [] }

    public var body: some View {
        NavigationSplitView {
            listContent
                .navigationTitle("Outfits")
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            if let selectedOutfitID, let outfit = outfits.first(where: { $0.id == selectedOutfitID }) {
                OutfitDetailView(outfit: outfit)
            } else {
                Text("Select an outfit")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if let errorMessage = gameData.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if gameData.isLoading {
            ProgressView("Loading outfits…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if outfits.isEmpty {
            Text("No outfits found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(outfits, selection: $selectedOutfitID) { outfit in
                VStack(alignment: .leading, spacing: 4) {
                    Text(outfit.name)
                        .font(.headline)

                    HStack {
                        Text("Tech \(outfit.techLevel)")
                        Text("\u{00B7}")
                        Text("\(outfit.cost) credits")
                        Text("\u{00B7}")
                        Text(OutfitDefinition.modTypeDescription(for: outfit.modType))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(outfit.id)
            }
        }
    }

}

private struct OutfitDetailView: View {
    let outfit: OutfitDefinition

    var body: some View {
        Form {
            Section("Outfit") {
                LabeledContent("Name", value: outfit.name)
                LabeledContent("ID", value: "\(outfit.id)")
                LabeledContent("Display Weight", value: "\(outfit.dispWeight)")
                LabeledContent("Mass", value: "\(outfit.mass) tons")
                LabeledContent("Tech Level", value: "\(outfit.techLevel)")
                LabeledContent("Cost", value: "\(outfit.cost) credits")
                LabeledContent("Max Owned", value: "\(outfit.max)")
                LabeledContent("Flags", value: "0x" + String(UInt16(bitPattern: outfit.flags), radix: 16))
            }

            Section("Primary Modification") {
                LabeledContent("ModType", value: "\(outfit.modType) - \(OutfitDefinition.modTypeDescription(for: outfit.modType))")
                LabeledContent("ModVal", value: "\(outfit.modVal)")
            }

            if outfit.modType2 != -1 {
                Section("Alternate Modification 2") {
                    LabeledContent("ModType2", value: "\(outfit.modType2) - \(OutfitDefinition.modTypeDescription(for: outfit.modType2))")
                    LabeledContent("ModVal2", value: "\(outfit.modVal2)")
                }
            }

            if outfit.modType3 != -1 {
                Section("Alternate Modification 3") {
                    LabeledContent("ModType3", value: "\(outfit.modType3) - \(OutfitDefinition.modTypeDescription(for: outfit.modType3))")
                    LabeledContent("ModVal3", value: "\(outfit.modVal3)")
                }
            }

            if outfit.modType4 != -1 {
                Section("Alternate Modification 4") {
                    LabeledContent("ModType4", value: "\(outfit.modType4) - \(OutfitDefinition.modTypeDescription(for: outfit.modType4))")
                    LabeledContent("ModVal4", value: "\(outfit.modVal4)")
                }
            }

            Section("Display Strings") {
                LabeledContent("Short Name", value: outfit.shortName.isEmpty ? "(none)" : outfit.shortName)
                LabeledContent("Lowercase Name", value: outfit.lcName.isEmpty ? "(none)" : outfit.lcName)
                LabeledContent("Lowercase Plural", value: outfit.lcPlural.isEmpty ? "(none)" : outfit.lcPlural)
            }

            Section("Purchase Rules") {
                LabeledContent("Item Class", value: "\(outfit.itemClass)")
                LabeledContent("Scan Mask", value: "0x" + String(UInt16(bitPattern: outfit.scanMask), radix: 16))
                LabeledContent("Buy Random", value: outfit.buyRandom < 0 ? "Always available" : "\(outfit.buyRandom)%")
                LabeledContent("Require Govt", value: "\(outfit.requireGovt) - \(OutfitDefinition.requireGovtDescription(for: outfit.requireGovt))")
            }

            if !outfit.availability.isEmpty || !outfit.onPurchase.isEmpty || !outfit.onSell.isEmpty {
                Section("Control Bit Expressions") {
                    if !outfit.availability.isEmpty {
                        LabeledContent("Availability", value: outfit.availability)
                    }
                    if !outfit.onPurchase.isEmpty {
                        LabeledContent("On Purchase", value: outfit.onPurchase)
                    }
                    if !outfit.onSell.isEmpty {
                        LabeledContent("On Sell", value: outfit.onSell)
                    }
                }
            }

            if outfit.contribute1 != 0 || outfit.contribute2 != 0 || outfit.require1 != 0 || outfit.require2 != 0 {
                Section("Contribute / Require") {
                    if outfit.contribute1 != 0 || outfit.contribute2 != 0 {
                        LabeledContent("Contribute", value: "0x" + String(UInt32(bitPattern: outfit.contribute1), radix: 16) + " " + String(UInt32(bitPattern: outfit.contribute2), radix: 16))
                    }
                    if outfit.require1 != 0 || outfit.require2 != 0 {
                        LabeledContent("Require", value: "0x" + String(UInt32(bitPattern: outfit.require1), radix: 16) + " " + String(UInt32(bitPattern: outfit.require2), radix: 16))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(outfit.name)
    }
}
