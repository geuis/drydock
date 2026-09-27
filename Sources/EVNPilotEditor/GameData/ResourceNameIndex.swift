import Foundation

// Pilot save files store many arrays indexed by (resource ID - 128): per star
// system, per planet/station, per character, per rank, per timed event, per
// disaster, per junk type, per government, and so on. The UI needs
// human-readable names for these indices, and resource names come straight
// from GameResource.name - no payload decoding needed, unlike the other
// GameData/*.swift decoders.
//
// Names are returned exactly as stored, including any ";comment" suffix some
// scenario resources carry (e.g. "Krim-Hwa Homeworld;used by mission 42") -
// stripping that is a caller concern, since some callers may want to show it
// and others may not.
public struct ResourceNameIndex: Sendable {
    private let namesByType: [String: [Int: String]]
    // Sorted once here because list views ask for these on every redraw.
    private let sortedEntriesByType: [String: [(id: Int, name: String)]]

    // Type codes indexed by default. GameDataLibrary already resolves
    // duplicate type+id resources (the later archive wins), so each ID here
    // has exactly one name.
    private static let indexedTypes: [String] = [
        systems, stellars, persons, ranks, crons, governments, junk, disasters,
        "shïp", "oütf", "wëap", "mïsn"
    ]

    public init(library: GameDataLibrary) {
        var result: [String: [Int: String]] = [:]

        for type in Self.indexedTypes {
            var byID: [Int: String] = [:]
            for resource in library.resources(ofType: type) {
                byID[resource.id] = resource.name
            }
            result[type] = byID
        }

        self.init(namesByType: result)
    }

    // For tests/previews - build an index directly from a name table without
    // needing real .rez data.
    public init(namesByType: [String: [Int: String]]) {
        self.namesByType = namesByType
        self.sortedEntriesByType = namesByType.mapValues { byID in
            byID
                .map { (id: $0.key, name: $0.value) }
                .sorted { $0.id < $1.id }
        }
    }

    public func name(type: String, id: Int) -> String? {
        namesByType[type]?[id]
    }

    // Sorted by id, since callers typically want to list "every system" etc.
    // in a stable, predictable order.
    public func entries(ofType type: String) -> [(id: Int, name: String)] {
        sortedEntriesByType[type] ?? []
    }

    // MARK: - Type code constants

    // Resource type codes are packed 4-character MacRoman codes (see
    // RezArchive's decodeMacRomanTypeCode) - these constants let callers
    // avoid hand-typing the accented characters.
    public static let systems = "sÿst"
    public static let stellars = "spöb"
    public static let persons = "përs"
    public static let ranks = "ränk"
    public static let crons = "crön"
    public static let governments = "gövt"
    public static let junk = "jünk"
    public static let disasters = "öops"
}
