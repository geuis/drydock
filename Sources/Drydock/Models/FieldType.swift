import Foundation

public enum ByteOrder: String, Codable, Sendable {
    case little, big
}

public struct FieldType: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case int16, int32, pascalString, cString, fixedBytes
    }

    public var kind: Kind
    public var byteOrder: ByteOrder?   // used for int16/int32
    public var maxLength: Int?          // used for pascalString/cString/fixedBytes

    public init(kind: Kind, byteOrder: ByteOrder? = nil, maxLength: Int? = nil) {
        self.kind = kind
        self.byteOrder = byteOrder
        self.maxLength = maxLength
    }
}
