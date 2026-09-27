import Foundation

// What the player's ship can really hold once owned outfits are counted.
// The shïp resource only gives stock figures; outfits such as cargo pods,
// fuel tanks, and mass expansions (which trade hold space for outfit space,
// e.g. the Mass Retool's -12 tons of cargo) change them, and the game
// checks the adjusted numbers - a mission flagged "needs cargo space" isn't
// offered without enough free hold.
public struct ShipCapacity: Sendable, Equatable {
    // One owned outfit's effect on a total, so the UI can say where the
    // number comes from.
    public struct Adjustment: Sendable, Equatable {
        public let outfitID: Int
        public let outfitName: String
        public let count: Int
        // Combined effect of every owned copy.
        public let amount: Int
    }

    // Outfit ModType values from the Nova Bible's oütf section.
    static let weaponModType: Int16 = 1
    static let cargoSpaceModType: Int16 = 2
    static let ammunitionModType: Int16 = 3
    static let fuelCapacityModType: Int16 = 12

    // Outfit flag: mass scales with the ship's own mass.
    static let massScalesWithShipFlag: Int16 = 0x0400

    public let baseCargo: Int
    public let cargoAdjustments: [Adjustment]
    public let tradeCargo: Int
    public let missionCargo: Int

    public let baseFuel: Int
    public let fuelAdjustments: [Adjustment]

    // Outfit space: the ship's FreeMass plus what its stock equipment
    // weighs (the Bible says FreeMass is "in addition to" stock weapons),
    // against what every owned outfit weighs.
    public let totalMass: Int
    public let usedMass: Int

    public var cargoCapacity: Int {
        max(baseCargo + cargoAdjustments.reduce(0) { $0 + $1.amount }, 0)
    }

    public var cargoAboard: Int {
        tradeCargo + missionCargo
    }

    public var freeCargo: Int {
        max(cargoCapacity - cargoAboard, 0)
    }

    public var fuelCapacity: Int {
        max(baseFuel + fuelAdjustments.reduce(0) { $0 + $1.amount }, 0)
    }

    public var freeMass: Int {
        totalMass - usedMass
    }

    // Reads everything it needs straight from the pilot bytes.
    public init(ship: ShipDefinition, outfitsByID: [Int: OutfitDefinition], pilotBytes: Data) {
        self.init(
            ship: ship,
            outfitsByID: outfitsByID,
            ownedOutfitCounts: PilotInventory.decodeItemCount(from: pilotBytes),
            tradeCargo: PilotProfile.decodeTradeCargo(from: pilotBytes),
            missionCargo: Self.activeMissionCargo(in: MissionSlot.decodeAll(from: pilotBytes))
        )
    }

    public init(
        ship: ShipDefinition,
        outfitsByID: [Int: OutfitDefinition],
        ownedOutfitCounts: [Int16],
        tradeCargo: [Int16],
        missionCargo: Int
    ) {
        let owned: [(outfit: OutfitDefinition, count: Int)] = Self.ownedOutfits(outfitsByID: outfitsByID, counts: ownedOutfitCounts)
        let shipMass: Int = Int(ship.mass)

        // A negative Holds only means "no mass expansions allowed".
        self.baseCargo = abs(Int(ship.holds))
        self.cargoAdjustments = Self.adjustments(for: Self.cargoSpaceModType, in: owned)
        self.tradeCargo = tradeCargo.reduce(0) { $0 + max(Int($1), 0) }
        self.missionCargo = missionCargo

        self.baseFuel = Int(ship.fuel)
        self.fuelAdjustments = Self.adjustments(for: Self.fuelCapacityModType, in: owned)

        self.totalMass = Int(ship.freeMass) + Self.stockMass(of: ship, outfitsByID: outfitsByID)
        self.usedMass = owned.reduce(0) { total, entry in
            total + entry.count * Self.mass(of: entry.outfit, shipMass: shipMass)
        }
    }

    // What one copy of an outfit weighs on this ship. Flag 0x0400 outfits
    // (armor plating and the like) weigh ship mass x outfit mass / 100.
    static func mass(of outfit: OutfitDefinition, shipMass: Int) -> Int {
        guard outfit.flags & massScalesWithShipFlag != 0, outfit.mass > 0 else { return Int(outfit.mass) }

        return shipMass * Int(outfit.mass) / 100
    }

    private static func ownedOutfits(outfitsByID: [Int: OutfitDefinition], counts: [Int16]) -> [(outfit: OutfitDefinition, count: Int)] {
        counts.indices.compactMap { index in
            let count: Int = Int(counts[index])
            guard count > 0, let outfit = outfitsByID[index + PilotStoryState.outfitIDBase] else { return nil }

            return (outfit, count)
        }
        .sorted { $0.outfit.id < $1.outfit.id }
    }

    private static func adjustments(for modType: Int16, in owned: [(outfit: OutfitDefinition, count: Int)]) -> [Adjustment] {
        owned.compactMap { entry in
            let perCopy: Int = modifications(of: entry.outfit)
                .filter { $0.type == modType }
                .reduce(0) { $0 + Int($1.value) }
            guard perCopy != 0 else { return nil }

            return Adjustment(outfitID: entry.outfit.id, outfitName: entry.outfit.name, count: entry.count, amount: perCopy * entry.count)
        }
    }

    // What the stock loadout weighs: default items, plus the outfit that
    // mounts each stock weapon and its ammunition.
    private static func stockMass(of ship: ShipDefinition, outfitsByID: [Int: OutfitDefinition]) -> Int {
        let shipMass: Int = Int(ship.mass)
        var total: Int = 0

        for (itemIDs, itemCounts) in [(ship.defaultItems, ship.itemCount), (ship.defaultItems2, ship.itemCount2)] {
            for slot in itemIDs.indices where slot < itemCounts.count && itemCounts[slot] > 0 {
                guard let outfit = outfitsByID[Int(itemIDs[slot])] else { continue }

                total += Int(itemCounts[slot]) * mass(of: outfit, shipMass: shipMass)
            }
        }

        for slot in ship.weapType.indices {
            let weaponID: Int16 = ship.weapType[slot]
            let count: Int = slot < ship.weapCount.count ? Int(ship.weapCount[slot]) : 0
            let ammo: Int = slot < ship.ammoLoad.count ? Int(ship.ammoLoad[slot]) : 0
            guard weaponID > 0 else { continue }

            if count > 0, let launcher = outfit(withMod: weaponModType, value: weaponID, in: outfitsByID) {
                total += count * mass(of: launcher, shipMass: shipMass)
            }

            if ammo > 0, let rounds = outfit(withMod: ammunitionModType, value: weaponID, in: outfitsByID) {
                total += ammo * mass(of: rounds, shipMass: shipMass)
            }
        }

        return total
    }

    // Lowest-ID outfit with this modification, so the answer is stable.
    private static func outfit(withMod modType: Int16, value: Int16, in outfitsByID: [Int: OutfitDefinition]) -> OutfitDefinition? {
        outfitsByID.values
            .filter { outfit in modifications(of: outfit).contains { $0.type == modType && $0.value == value } }
            .min { $0.id < $1.id }
    }

    // Every active mission's cargo, counted in full: the pilot file doesn't
    // say whether cargo picked up mid-mission is aboard yet, so this can
    // overstate what's in the hold for such missions.
    static func activeMissionCargo(in slots: [MissionSlot]) -> Int {
        slots
            .filter(\.isActive)
            .reduce(0) { $0 + max(Int($1.cargoQty), 0) }
    }

    private static func modifications(of outfit: OutfitDefinition) -> [(type: Int16, value: Int16)] {
        [
            (outfit.modType, outfit.modVal),
            (outfit.modType2, outfit.modVal2),
            (outfit.modType3, outfit.modVal3),
            (outfit.modType4, outfit.modVal4)
        ]
    }
}
