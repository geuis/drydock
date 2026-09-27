import Foundation

// Aggregates resources across every .rez archive in a game data folder
// (e.g. EV Nova's "Nova Files" directory, which ships Nova Data 1-6.rez,
// Nova Ships 1-8.rez, Nova Graphics 1-3.rez, etc.) and the plug-ins folder
// into one combined, queryable set.
//
// When two archives define a resource of the same type+id, the one loaded
// later replaces the earlier one, the way EV Nova lets plug-ins override
// the base game. Resolving it once here means every catalog, name lookup,
// and mission index agrees on which definition is in effect.
public final class GameDataLibrary {
    public let resources: [GameResource]

    // Archives that failed to parse are recorded here rather than failing
    // the whole library load - one corrupt or unsupported .rez file
    // shouldn't prevent using the rest (e.g. graphics/sound/title archives
    // that may not follow this same layout).
    public let failedArchives: [(url: URL, error: Error)]

    public convenience init(contentsOfDirectory directoryURL: URL) throws {
        try self.init(baseDirectory: directoryURL, pluginsDirectory: nil)
    }

    // Loads the base game folder, then every plug-in, so plug-ins override
    // the base game. The plug-ins folder is optional: a missing one just
    // means no plug-ins. Plug-ins may sit in subfolders.
    public init(baseDirectory: URL, pluginsDirectory: URL?) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let baseFileURLs: [URL] = contents
            .filter { $0.pathExtension.lowercased() == "rez" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let pluginFileURLs: [URL] = pluginsDirectory.map(Self.pluginFileURLs(in:)) ?? []
        let rezFileURLs: [URL] = baseFileURLs + pluginFileURLs

        var mergedResources: [GameResource] = []
        var failures: [(url: URL, error: Error)] = []
        // Where each type+id sits in mergedResources, so a later duplicate
        // replaces it in place and the order stays stable.
        var indexByKey: [String: Int] = [:]

        for fileURL in rezFileURLs {
            do {
                let archive = try RezArchive(contentsOf: fileURL)

                for resource in archive.resources {
                    let key: String = "\(resource.type)#\(resource.id)"

                    if let existingIndex = indexByKey[key] {
                        mergedResources[existingIndex] = resource
                    } else {
                        indexByKey[key] = mergedResources.count
                        mergedResources.append(resource)
                    }
                }
            } catch {
                failures.append((url: fileURL, error: error))
            }
        }

        self.resources = mergedResources
        self.failedArchives = failures
    }

    // Every .rez under the plug-ins folder, in path order so the result is
    // the same on every launch.
    private static func pluginFileURLs(in directoryURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "rez" }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public func resources(ofType type: String) -> [GameResource] {
        resources.filter { $0.type == type }
    }

    public func resource(ofType type: String, id: Int) -> GameResource? {
        resources.first { $0.type == type && $0.id == id }
    }
}
