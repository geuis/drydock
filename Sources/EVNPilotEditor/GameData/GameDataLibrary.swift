import Foundation

// Aggregates resources across every .rez archive in a game data folder
// (e.g. EV Nova's "Nova Files" directory, which ships Nova Data 1-6.rez,
// Nova Ships 1-8.rez, Nova Graphics 1-3.rez, etc.) into one combined,
// queryable set.
//
// Later-loaded files do NOT overwrite earlier ones: if two archives both
// define a resource of the same type+id, both are kept as separate entries
// (this can legitimately happen when a scenario's data is split across
// multiple files). Callers needing a single canonical resource should
// decide their own precedence for now.
public final class GameDataLibrary {
    public let resources: [GameResource]

    // Archives that failed to parse are recorded here rather than failing
    // the whole library load - one corrupt or unsupported .rez file
    // shouldn't prevent using the rest (e.g. graphics/sound/title archives
    // that may not follow this same layout).
    public let failedArchives: [(url: URL, error: Error)]

    public init(contentsOfDirectory directoryURL: URL) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let rezFileURLs = contents
            .filter { $0.pathExtension.lowercased() == "rez" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var mergedResources: [GameResource] = []
        var failures: [(url: URL, error: Error)] = []

        for fileURL in rezFileURLs {
            do {
                let archive = try RezArchive(contentsOf: fileURL)

                // Duplicates across archives are expected and kept (see
                // class doc above).
                mergedResources.append(contentsOf: archive.resources)
            } catch {
                failures.append((url: fileURL, error: error))
            }
        }

        self.resources = mergedResources
        self.failedArchives = failures
    }

    public func resources(ofType type: String) -> [GameResource] {
        resources.filter { $0.type == type }
    }

    public func resource(ofType type: String, id: Int) -> GameResource? {
        resources.first { $0.type == type && $0.id == id }
    }
}
