import Foundation

// Plain-English messages for the app's error types. Without these, alerts
// showed "The operation couldn't be completed (... error 1)", which doesn't
// say whether, for example, the backup or the write failed.

extension PilotFileError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileTooSmall:
            return "The file is too small to be an EV Nova pilot."
        case .backupFailed:
            return "The backup copy couldn't be written, so the pilot file was left untouched. Check that the Pilots folder is writable."
        case .writeFailed:
            return "The pilot file couldn't be written. The file on disk was left as it was."
        case .changedOnDisk:
            return "The pilot file was changed by something else (usually EV Nova) after it was opened."
        }
    }
}

extension ByteReaderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .outOfBounds:
            return "Tried to read past the end of the file."
        case .invalidEncoding:
            return "The text in the file couldn't be read."
        }
    }
}

extension ByteWriterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .outOfBounds:
            return "Tried to write past the end of the file."
        case .valueTooLarge:
            return "That value doesn't fit in this field."
        case .unsupportedFieldType:
            return "This kind of field can't be edited."
        case .unencodableCharacters:
            return "That text has characters EV Nova can't store. Use plain letters, digits, and common accented letters."
        }
    }
}

extension PilotArrayError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .indexOutOfRange:
            return "That entry number is outside the list the pilot file holds."
        case .dataOutOfBounds:
            return "The pilot file is too short to hold this entry."
        }
    }
}

extension MissionBitsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .indexOutOfRange:
            return "Story flag numbers run from 0 to \(MissionBits.count - 1)."
        case .dataOutOfBounds:
            return "The pilot file is too short to hold the story flags."
        }
    }
}

extension MissionSlotError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidIndex:
            return "There is no mission slot with that number."
        case .outOfBounds:
            return "The pilot file is too short to hold this mission slot."
        }
    }
}

extension PilotShipIdentityError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "The ship name can't be empty."
        case .nameTooLong:
            return "The ship name can be at most \(PilotShipIdentity.maxNameLength) characters."
        case .unencodableCharacters:
            return "That ship name has characters EV Nova can't store."
        case .dataOutOfBounds:
            return "The pilot file is too short to hold a ship name."
        }
    }
}

extension PilotUniverseStateError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .indexOutOfRange:
            return "That entry number is outside the list the pilot file holds."
        case .dataOutOfBounds:
            return "The pilot file is too short to hold this value."
        case .unencodableString:
            return "That text has characters EV Nova can't store."
        }
    }
}

extension RezArchiveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidSignature:
            return "Not an EV Nova data file (.rez)."
        case .unsupportedGroupCount(let count):
            return "Unsupported .rez layout (\(count) groups)."
        case .unsupportedGroupType(let type):
            return "Unsupported .rez layout (group type \(type))."
        case .noEntries:
            return "The .rez file is empty."
        case .invalidResourceIndex(let index):
            return "The .rez file is damaged (resource index \(index))."
        case .truncated:
            return "The .rez file is damaged or cut short."
        }
    }
}
