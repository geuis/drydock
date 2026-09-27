import Foundation

// A mission's PayVal decoded into what the player actually gets (Nova
// Bible, mïsn PayVal). Negative values are special codes, not negative
// credit amounts. Shared by the mission catalog and the pilot's current
// missions so both read the codes the same way.
public enum MissionPay: Equatable, Sendable {
    public enum RecordScope: Equatable, Sendable {
        case government
        case withAllies
        case withClassmates
    }

    case none
    case credits(Int)
    // Clears the player's legal record with a government (resource ID).
    case clearRecord(governmentID: Int, scope: RecordScope)
    case takePercentOfCash(Int)
    case takeCreditsAtStart(Int)
    case unrecognized(Int)

    public init(_ payVal: Int32) {
        let value: Int = Int(payVal)

        switch value {
        case 0, -1:
            self = .none
        case 1...:
            self = .credits(value)
        case -10383...(-10128):
            self = .clearRecord(governmentID: -value - 10000, scope: .government)
        case -20383...(-20128):
            self = .clearRecord(governmentID: -value - 20000, scope: .withAllies)
        case -30383...(-30128):
            self = .clearRecord(governmentID: -value - 30000, scope: .withClassmates)
        case -40099...(-40001):
            self = .takePercentOfCash(-value - 40000)
        case ...(-50000):
            self = .takeCreditsAtStart(-value - 50000)
        default:
            self = .unrecognized(value)
        }
    }

    // Plain-English wording. `governmentName` turns a government resource
    // ID into a display name; callers without game data can leave it out.
    public func description(governmentName: (Int) -> String = { "government \($0)" }) -> String {
        switch self {
        case .none:
            return "No pay"
        case .credits(let amount):
            return "\(amount) credits"
        case .clearRecord(let governmentID, .government):
            return "Clears legal record with \(governmentName(governmentID))"
        case .clearRecord(let governmentID, .withAllies):
            return "Clears legal record with \(governmentName(governmentID)) and its allies"
        case .clearRecord(let governmentID, .withClassmates):
            return "Clears legal record with \(governmentName(governmentID)) and its classmates"
        case .takePercentOfCash(let percent):
            return "Takes \(percent)% of your cash"
        case .takeCreditsAtStart(let amount):
            return "Takes \(amount) credits at mission start"
        case .unrecognized(let value):
            return "Unknown special reward (\(value))"
        }
    }
}
