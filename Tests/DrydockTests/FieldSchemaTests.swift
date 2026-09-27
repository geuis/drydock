import XCTest
@testable import Drydock

final class FieldSchemaTests: XCTestCase {
    // The bundled list used to name only 2 of the 10 bundled fields, so
    // persisting a discovered field also copied cash, rating, fuel, etc.
    // into the user's override file.
    func testEveryBundledFieldCountsAsBundled() {
        let schema = FieldSchema.loadDefault()
        let bundledIDs: [String] = ["shipName", "shipClassName", "cash", "rating", "lastStellar", "shipClass", "fuel", "gameMonth", "gameDay", "gameYear"]

        for id in bundledIDs {
            XCTAssertTrue(schema.isBundledField(id), "\(id) should count as bundled")
        }

        XCTAssertFalse(schema.isBundledField("somethingDiscovered"))
    }
}
