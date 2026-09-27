import Foundation

// One star system (sÿst) as the galaxy map needs it: where it sits, which
// systems it has hyperlinks to, which planets and stations it holds, and who
// owns it.
//
// Nova Bible, "The sÿst resource" (lines 3005-3134). Field order on disk is
// xPos, yPos, Con[16], Nav[16], DudeType[8], Prob[8], AvgShips, Govt, ...
// with every field a big-endian short and no padding. That order puts
// Visibility at byte 150, the offset SystemSource already confirmed against
// all 545 real systems, so the earlier offsets below follow from it.
public struct StarSystemDefinition: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    // Map coordinates, the same ones the in-game map uses. Y grows downward.
    public let x: Int
    public let y: Int
    // Hyperlinked system IDs (empty slots removed).
    public let connectionIDs: [Int]
    // Planet and station (spöb) IDs in this system (empty slots removed).
    public let stellarIDs: [Int]
    // Owning government's resource ID, or nil for independent.
    public let governmentID: Int?

    enum Layout {
        static let xPos = 0
        static let yPos = 2
        static let connectionsStart = 4
        static let connectionCount = 16
        static let navsStart = 36
        static let navCount = 16
        static let government = 102
    }

    public static func decodeAll(from library: GameDataLibrary) -> [StarSystemDefinition] {
        library.resources(ofType: ResourceNameIndex.systems).compactMap(decode)
    }

    static func decode(_ resource: GameResource) -> StarSystemDefinition? {
        let reader = ByteReader(resource.data)

        do {
            let x = try reader.int16(at: Layout.xPos, byteOrder: .big)
            let y = try reader.int16(at: Layout.yPos, byteOrder: .big)
            let connections = try readIDs(reader, start: Layout.connectionsStart, count: Layout.connectionCount)
            let stellars = try readIDs(reader, start: Layout.navsStart, count: Layout.navCount)
            let government = try reader.int16(at: Layout.government, byteOrder: .big)

            return StarSystemDefinition(
                id: resource.id,
                name: resource.name,
                x: Int(x),
                y: Int(y),
                connectionIDs: connections,
                stellarIDs: stellars,
                governmentID: government >= 128 ? Int(government) : nil
            )
        } catch {
            return nil
        }
    }

    // Unused Con/Nav slots hold -1 (or 0 in some plugin data).
    private static func readIDs(_ reader: ByteReader, start: Int, count: Int) throws -> [Int] {
        var ids: [Int] = []

        for slot in 0..<count {
            let value = try reader.int16(at: start + slot * 2, byteOrder: .big)

            if value >= 128 {
                ids.append(Int(value))
            }
        }

        return ids
    }
}

// Every system plus the lookups the map and mission "find" need, built once
// with the rest of the game data snapshot.
public struct GalaxyMap: Sendable {
    public struct Link: Hashable, Sendable {
        public let fromID: Int
        public let toID: Int
    }

    public let systems: [StarSystemDefinition]
    public let systemsByID: [Int: StarSystemDefinition]
    // A planet can be listed by more than one system in plugin data; the
    // lowest system ID wins so the answer is stable.
    public let systemIDByStellarID: [Int: Int]
    // Each hyperlink once, whichever end lists it.
    public let links: [Link]
    // Bounding box of every system's coordinates.
    public let minX: Int
    public let minY: Int
    public let maxX: Int
    public let maxY: Int

    public init(systems unsortedSystems: [StarSystemDefinition]) {
        let systems: [StarSystemDefinition] = unsortedSystems.sorted { $0.id < $1.id }
        let systemsByID: [Int: StarSystemDefinition] = Dictionary(systems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var systemIDByStellarID: [Int: Int] = [:]

        for system in systems {
            for stellarID in system.stellarIDs where systemIDByStellarID[stellarID] == nil {
                systemIDByStellarID[stellarID] = system.id
            }
        }

        var seenLinks: Set<Link> = []
        var links: [Link] = []

        for system in systems {
            for otherID in system.connectionIDs where systemsByID[otherID] != nil && otherID != system.id {
                let link = Link(fromID: min(system.id, otherID), toID: max(system.id, otherID))

                if seenLinks.insert(link).inserted {
                    links.append(link)
                }
            }
        }

        self.systems = systems
        self.systemsByID = systemsByID
        self.systemIDByStellarID = systemIDByStellarID
        self.links = links
        self.minX = systems.map(\.x).min() ?? 0
        self.minY = systems.map(\.y).min() ?? 0
        self.maxX = systems.map(\.x).max() ?? 0
        self.maxY = systems.map(\.y).max() ?? 0
    }

    public init(library: GameDataLibrary) {
        self.init(systems: StarSystemDefinition.decodeAll(from: library))
    }

    public func systemID(containingStellar stellarID: Int) -> Int? {
        systemIDByStellarID[stellarID]
    }

    // Systems one jump away, whichever end lists the hyperlink.
    public func neighborIDs(of systemID: Int) -> [Int] {
        var result: Set<Int> = Set(systemsByID[systemID]?.connectionIDs ?? [])

        for system in systems where system.connectionIDs.contains(systemID) {
            result.insert(system.id)
        }

        result.remove(systemID)
        return result.filter { systemsByID[$0] != nil }.sorted()
    }

    public func systemIDs(ownedBy governmentID: Int) -> [Int] {
        systems.filter { $0.governmentID == governmentID }.map(\.id)
    }
}
