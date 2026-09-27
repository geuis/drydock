import Foundation

// A mission's places, handed to the Map tab by a "Find on Map" button.
struct MapFocus: Equatable {
    let id = UUID()
    let missionID: Int
    let title: String
    let locations: [MissionMapLocation]
}

// The open pilot's last planet or station (a spöb resource ID).
struct PilotLocation: Equatable {
    let pilotName: String
    let stellarID: Int
}

// Which top-level tab is showing, and what the Map tab should point at.
// Shared app-wide so a button deep in the Pilots tab can switch to the map.
@MainActor
final class AppNavigator: ObservableObject {
    enum Tab: Hashable {
        case pilots
        case gameData
        case map
    }

    @Published var tab: Tab = .pilots
    @Published var mapFocus: MapFocus?
    // Where the open pilot last landed, so the map can mark their system.
    @Published var pilotLocation: PilotLocation?

    func showOnMap(_ focus: MapFocus) {
        mapFocus = focus
        tab = .map
    }
}
