import XCTest
@testable import EVNPilotEditor

final class StockLoadoutTests: XCTestCase {
    private func makeShip(
        weapType: [Int16],
        weapCount: [Int16],
        ammoLoad: [Int16],
        defaultItems: [Int16],
        itemCount: [Int16]
    ) -> ShipDefinition {
        ShipDefinition(
            id: 128, name: "Test Ship", holds: 0, shield: 0, accel: 0, speed: 0, maneuver: 0, fuel: 0,
            freeMass: 0, armor: 0, shieldRecharge: 0,
            weapType: weapType, weapCount: weapCount, ammoLoad: ammoLoad,
            maxGun: 0, maxTur: 0, techLevel: 0, cost: 0, deathDelay: 0, armorRecharge: 0,
            explode1: 0, explode2: 0, dispWeight: 0, mass: 0, length: 0, inherentAI: 0, crew: 0,
            strength: 0, inherentGovt: 0, flags: 0, podCount: 0,
            defaultItems: defaultItems, itemCount: itemCount,
            fuelRegen: 0, skillVar: 0, flags2: 0, availability: "", appearOn: "", onPurchase: "",
            deionize: 0, ionizeMax: 0, keyCarried: 0, defaultItems2: [], itemCount2: [],
            contribute1: 0, contribute2: 0, require1: 0, require2: 0, buyRandom: 0, hireRandom: 0,
            onCapture: "", onRetire: "", subtitle: "", flags3: 0, upgradeTo: 0, escUpgrdCost: 0,
            escSellValue: 0, escortType: 0, shortName: "", commName: "", longName: "", movieFile: ""
        )
    }

    private func fixtureBytes() throws -> Data {
        guard let url = Bundle.module.url(forResource: "Shane Merrol", withExtension: "plt", subdirectory: "Fixtures") else {
            throw XCTSkip("Fixture not found")
        }

        return try Data(contentsOf: url)
    }

    func testSameWeaponInTwoSlotsAddsBothSlots() throws {
        var data = try fixtureBytes()
        let weaponIndex: Int = 10
        let outfitIndex: Int = 20
        try PilotInventory.setWeapCount(1, at: weaponIndex, in: &data)
        try PilotInventory.setAmmo(5, at: weaponIndex, in: &data)
        try PilotInventory.setItemCount(0, at: outfitIndex, in: &data)

        let ship = makeShip(
            weapType: [Int16(weaponIndex + 128), Int16(weaponIndex + 128), -1],
            weapCount: [2, 3, 0],
            ammoLoad: [10, 20, 0],
            defaultItems: [Int16(outfitIndex + 128), Int16(outfitIndex + 128)],
            itemCount: [1, 4]
        )

        try PilotInventory.addStockLoadout(of: ship, in: &data)

        XCTAssertEqual(PilotInventory.decodeWeapCount(from: data)[weaponIndex], 1 + 2 + 3)
        XCTAssertEqual(PilotInventory.decodeAmmo(from: data)[weaponIndex], 5 + 10 + 20)
        XCTAssertEqual(PilotInventory.decodeItemCount(from: data)[outfitIndex], 1 + 4)
    }

    func testCountsStopAtTheLargestStorableValue() {
        XCTAssertEqual(PilotInventory.clampedSum(Int16.max - 1, 5), Int16.max)
        XCTAssertEqual(PilotInventory.clampedSum(-3, 2), 2)
    }
}
