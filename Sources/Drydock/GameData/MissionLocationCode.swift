import Foundation

// A mission's AvailStel / TravelStel / ReturnStel code, decoded into what it
// points at (Nova Bible, mïsn AvailStel). One decoder so the details view,
// the map, and the diagnostics text can't disagree on the arithmetic.
//
// System and government codes store (resource ID - 128). In the
// "government" range, 9999 is (-1 + 10000): independent worlds.
enum MissionLocationCode: Equatable {
    case anyInhabited
    case stellar(Int)
    case adjacentToSystem(Int)
    // nil government = independents.
    case government(Int?)
    case allyOf(Int?)
    case notGovernment(Int?)
    case enemyOf(Int?)
    case governmentOrClass(Int?)
    case neitherGovernmentNorClass(Int?)
    case unrecognized(Int)

    init(_ code: Int16) {
        let value: Int = Int(code)

        switch value {
        case -1:
            self = .anyInhabited
        case 128...2175:
            self = .stellar(value)
        case 5000...7047:
            self = .adjacentToSystem(value - 5000 + 128)
        case 9999...10255:
            self = .government(Self.governmentID(value - 10000))
        case 15000...15255:
            self = .allyOf(Self.governmentID(value - 15000))
        case 20000...20255:
            self = .notGovernment(Self.governmentID(value - 20000))
        case 25000...25255:
            self = .enemyOf(Self.governmentID(value - 25000))
        case 30000...30255:
            self = .governmentOrClass(Self.governmentID(value - 30000))
        case 31000...31255:
            self = .neitherGovernmentNorClass(Self.governmentID(value - 31000))
        default:
            self = .unrecognized(value)
        }
    }

    private static func governmentID(_ index: Int) -> Int? {
        index < 0 ? nil : index + 128
    }
}
