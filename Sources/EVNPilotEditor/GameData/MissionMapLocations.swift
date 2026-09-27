import Foundation

// Where a mission sends the player, as systems on the galaxy map. Built from
// the mission's AvailStel, TravelStel, ReturnStel, and ShipSyst fields (see
// MissionDefinition), using the Nova Bible's documented value ranges.
//
// Many codes don't name one place ("any planet of the Federation", "a
// random inhabited planet"). Those that narrow to a set of systems mark all
// of them; those that don't still get a line of text, with no systems.
public struct MissionMapLocation: Identifiable, Equatable, Sendable {
    public enum Role: String, CaseIterable, Sendable {
        case offered = "Offered at"
        case destination = "Travel to"
        case returnTo = "Return to"
        case specialShips = "Special ships"
    }

    public let role: Role
    public let description: String
    public let systemIDs: [Int]

    public var id: String { role.rawValue }
}

public enum MissionMapLocations {
    // A live mission's slot stores the planets it actually picked, which
    // beat the definition's "random planet" codes. Pass them when known.
    public static func locations(
        for mission: MissionDefinition,
        galaxy: GalaxyMap,
        names: ResourceNameIndex,
        chosenTravelStel: Int16? = nil,
        chosenReturnStel: Int16? = nil
    ) -> [MissionMapLocation] {
        let travelStel: Int16 = pick(chosenTravelStel, over: mission.travelStel)
        let returnStel: Int16 = pick(chosenReturnStel, over: mission.returnStel)

        var result: [MissionMapLocation] = []

        result.append(MissionMapLocation(
            role: .offered,
            description: MissionPlaces.offeredAt(mission.availStel, names: names),
            systemIDs: stellarCodeSystems(mission.availStel, galaxy: galaxy)
        ))

        if let travel = objective(.destination, code: travelStel, galaxy: galaxy, names: names) {
            result.append(travel)
        }

        if let returnLocation = objective(.returnTo, code: returnStel, galaxy: galaxy, names: names) {
            result.append(returnLocation)
        }

        if mission.shipCount > 0, let ships = specialShips(mission, travelStel: travelStel, returnStel: returnStel, galaxy: galaxy, names: names) {
            result.append(ships)
        }

        return result
    }

    // MARK: - Stellar codes

    // Systems a stellar-style location code (AvailStel, TravelStel,
    // ReturnStel) can land in. Empty when it could be anywhere.
    static func stellarCodeSystems(_ code: Int16, galaxy: GalaxyMap) -> [Int] {
        let value: Int = Int(code)

        switch value {
        case 128...2175:
            return galaxy.systemID(containingStellar: value).map { [$0] } ?? []

        case 5000...7047:
            return galaxy.neighborIDs(of: value - 5000 + 128)

        case 9999...10255:
            // 9999 is (-1 + 10000): independent worlds.
            let governmentIndex: Int = value - 10000
            return governmentIndex < 0 ? [] : galaxy.systemIDs(ownedBy: governmentIndex + 128)

        default:
            return []
        }
    }

    private static func objective(_ role: MissionMapLocation.Role, code: Int16, galaxy: GalaxyMap, names: ResourceNameIndex) -> MissionMapLocation? {
        switch code {
        case -1, 0:
            return nil

        case -2:
            return MissionMapLocation(role: role, description: "A random inhabited planet, picked when you accept", systemIDs: [])

        case -3:
            return MissionMapLocation(role: role, description: "A random uninhabited planet, picked when you accept", systemIDs: [])

        case -4 where role == .returnTo:
            return MissionMapLocation(role: role, description: "Back where you accepted it", systemIDs: [])

        case ...(-4):
            return MissionMapLocation(role: role, description: "Picked when you accept (code \(code))", systemIDs: [])

        default:
            return MissionMapLocation(
                role: role,
                description: MissionPlaces.offeredAt(code, names: names),
                systemIDs: stellarCodeSystems(code, galaxy: galaxy)
            )
        }
    }

    // MARK: - Special ships

    // ShipSyst names a system directly (not a planet), or one of six
    // sentinels relative to the mission's other places.
    private static func specialShips(_ mission: MissionDefinition, travelStel: Int16, returnStel: Int16, galaxy: GalaxyMap, names: ResourceNameIndex) -> MissionMapLocation? {
        let value: Int = Int(mission.shipSyst)

        let described: (String, [Int]) = {
            switch value {
            case -1:
                return ("In the system where you accept the mission", [])

            case -2:
                return ("In the destination system", stellarCodeSystems(travelStel, galaxy: galaxy))

            case -3:
                return ("In a random system", [])

            case -4:
                return ("In the return system", stellarCodeSystems(returnStel, galaxy: galaxy))

            case -5:
                return ("In a system next to where you accept the mission", [])

            case -6:
                return ("Following you from system to system", [])

            case 128...2175:
                let name: String = names.name(type: ResourceNameIndex.systems, id: value).map { GameName($0).title } ?? "System \(value)"
                return ("In \(name)", galaxy.systemsByID[value] == nil ? [] : [value])

            default:
                return ("System code \(value)", [])
            }
        }()

        return MissionMapLocation(role: .specialShips, description: described.0, systemIDs: described.1)
    }

    // A slot's stored planet wins when it's a real planet ID.
    private static func pick(_ chosen: Int16?, over definition: Int16) -> Int16 {
        guard let chosen, chosen >= 128 else { return definition }
        return chosen
    }
}
