import Foundation

public enum FieldConfidence: String, Codable, Sendable {
    case verified, probable, unknown
}

public struct FieldDefinition: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var offset: Int   // absolute byte offset from start of file
    public var length: Int   // total reserved byte span; -1 means variable/runs-to-EOF (never written to)
    public var type: FieldType
    public var group: String // UI grouping label, e.g. "Identity"
    public var confidence: FieldConfidence
    public var editable: Bool

    public init(id: String, name: String, offset: Int, length: Int, type: FieldType, group: String, confidence: FieldConfidence, editable: Bool) {
        self.id = id; self.name = name; self.offset = offset; self.length = length
        self.type = type; self.group = group; self.confidence = confidence; self.editable = editable
    }
}
