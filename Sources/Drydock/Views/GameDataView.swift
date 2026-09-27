import SwiftUI

// Root browser for the game's own scenario data (ships/outfits/weapons),
// as opposed to pilot save files. Sibling to PilotWorkspaceView.
public struct GameDataView: View {
    private enum Category: String, CaseIterable, Identifiable {
        case ships = "Ships"
        case outfits = "Outfits"
        case weapons = "Weapons"
        case missions = "Missions"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .ships: return "airplane"
            case .outfits: return "shippingbox"
            case .weapons: return "bolt.fill"
            case .missions: return "flag.checkered"
            }
        }
    }

    @State private var selection: Category? = .ships

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(Category.allCases, selection: $selection) { category in
                Label(category.rawValue, systemImage: category.icon)
                    .tag(category)
            }
            .navigationTitle("Game Data")
        } detail: {
            switch selection {
            case .ships:
                ShipCatalogView()
            case .outfits:
                OutfitCatalogView()
            case .weapons:
                WeaponCatalogView()
            case .missions:
                MissionCatalogView()
            case nil:
                Text("Select a category")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
