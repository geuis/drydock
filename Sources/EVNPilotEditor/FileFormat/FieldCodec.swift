import Foundation

// Glue between a FieldDefinition and the ByteReader/ByteWriter primitives.
// Editability enforcement (field.editable == false) lives in PilotFile, not here.
public enum FieldCodec {
    public static func decode(_ field: FieldDefinition, from data: Data) throws -> PilotFieldValue {
        let reader = ByteReader(data)

        switch field.type.kind {
        case .int16:
            let byteOrder = field.type.byteOrder ?? .little
            let value = try reader.int16(at: field.offset, byteOrder: byteOrder)
            return .int(Int(value))

        case .int32:
            let byteOrder = field.type.byteOrder ?? .little
            let value = try reader.int32(at: field.offset, byteOrder: byteOrder)
            return .int(Int(value))

        case .pascalString:
            let maxLength = field.type.maxLength ?? max(field.length - 1, 0)
            let value = try reader.pascalString(at: field.offset, maxLength: maxLength)
            return .string(value)

        case .cString:
            let maxLength = field.type.maxLength ?? Int.max
            let value = try reader.cString(at: field.offset, maxLength: maxLength)
            return .string(value)

        case .fixedBytes:
            guard field.length >= 0 else {
                throw ByteReaderError.outOfBounds
            }
            let value = try reader.bytes(at: field.offset, length: field.length)
            return .bytes(value)
        }
    }

    public static func encode(_ value: PilotFieldValue, for field: FieldDefinition, into data: inout Data) throws {
        switch field.type.kind {
        case .int16:
            guard case .int(let intValue) = value else {
                throw ByteWriterError.valueTooLarge
            }
            guard let int16Value = Int16(exactly: intValue) else {
                throw ByteWriterError.valueTooLarge
            }
            let byteOrder = field.type.byteOrder ?? .little
            try ByteWriter.writeInt16(int16Value, at: field.offset, byteOrder: byteOrder, into: &data)

        case .int32:
            guard case .int(let intValue) = value else {
                throw ByteWriterError.valueTooLarge
            }
            guard let int32Value = Int32(exactly: intValue) else {
                throw ByteWriterError.valueTooLarge
            }
            let byteOrder = field.type.byteOrder ?? .little
            try ByteWriter.writeInt32(int32Value, at: field.offset, byteOrder: byteOrder, into: &data)

        case .pascalString:
            guard case .string(let stringValue) = value else {
                throw ByteWriterError.valueTooLarge
            }
            let maxLength = field.type.maxLength ?? max(field.length - 1, 0)
            try ByteWriter.writePascalString(stringValue, at: field.offset, maxLength: maxLength, into: &data)

        case .cString, .fixedBytes:
            // Not supported for writing in v1 - see ByteWriter for rationale.
            throw ByteWriterError.unsupportedFieldType
        }
    }
}
