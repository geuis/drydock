import Foundation

public enum PilotFieldValue: Equatable, Sendable {
    case int(Int)
    case string(String)
    case bytes(Data)

    // Short human-readable representation for UI display, regardless of case.
    public var displayString: String {
        switch self {
        case .int(let value):
            return "\(value)"

        case .string(let value):
            return value

        case .bytes(let data):
            return "\(data.count) bytes"
        }
    }
}
