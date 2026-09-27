import Foundation

public struct GameDataSnapshot: Sendable {
    public let ships: [ShipDefinition]
    public let outfits: [OutfitDefinition]
    public let weapons: [WeaponDefinition]
    // ID lookups built once here; rebuilding them inside views made every
    // redraw scan the whole catalog for each row.
    public let shipsByID: [Int: ShipDefinition]
    public let outfitsByID: [Int: OutfitDefinition]
    public let weaponsByID: [Int: WeaponDefinition]
    public let missions: [MissionDefinition]
    public let missionResolver: MissionChainResolver
    public let missionChains: [MissionChainComponent]
    // Pilot-independent mission analysis, reused for every diagnosis.
    public let missionAnalysis: MissionDiagnostics.Prepared
    public let storyFlags: [Int: StoryFlagMetadata]
    // dësc text by resource ID, for showing what missions say.
    public let descriptions: [Int: String]
    public let names: ResourceNameIndex
    public let galaxy: GalaxyMap
    public let failedArchiveCount: Int
}

// Application-scoped immutable scenario data. The .rez archives are static
// for an app session, so all parsing and derived-index construction happens
// once during launch rather than independently in each screen.
@MainActor
public final class GameDataStore: ObservableObject {
    // Nil until the user has pointed the app at their EV Nova install.
    public private(set) var directoryURL: URL?

    @Published public private(set) var snapshot: GameDataSnapshot?
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private var loadTask: Task<Void, Never>?

    public init(directoryURL: URL?) {
        self.directoryURL = directoryURL
    }

    public func loadOnce() {
        guard snapshot == nil, loadTask == nil else { return }

        guard let directoryURL = self.directoryURL else {
            errorMessage = "Choose your EV Nova folder in Settings."
            return
        }

        isLoading = true
        errorMessage = nil

        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.makeSnapshot(directoryURL: directoryURL)
            }.value

            // A newer folder was chosen while this one was parsing; its own
            // load owns the published state now.
            guard directoryURL == self.directoryURL else { return }

            switch result {
            case .success(let loadedSnapshot):
                snapshot = loadedSnapshot
            case .failure(let message):
                errorMessage = message
            }
            isLoading = false
            loadTask = nil
        }
    }

    // Swaps in a different install without restarting the app, e.g. when the
    // user picks their game folder on first launch or changes it in Settings.
    public func reload(directoryURL newDirectoryURL: URL?) {
        guard newDirectoryURL != directoryURL || snapshot == nil else { return }

        loadTask?.cancel()
        loadTask = nil
        snapshot = nil
        isLoading = false
        errorMessage = nil
        directoryURL = newDirectoryURL

        loadOnce()
    }

    private enum LoadResult: Sendable {
        case success(GameDataSnapshot)
        case failure(String)
    }

    nonisolated private static func makeSnapshot(directoryURL: URL) -> LoadResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure("Nova Files folder not found:\n\(directoryURL.path)\n\nChoose your EV Nova folder in Settings.")
        }

        do {
            // Plug-ins live next to Nova Files in the game folder.
            let pluginsURL: URL = directoryURL
                .deletingLastPathComponent()
                .appendingPathComponent(AppSettings.pluginsFolderName, isDirectory: true)
            let library = try GameDataLibrary(baseDirectory: directoryURL, pluginsDirectory: pluginsURL)
            let ships = ShipDefinition.decodeAll(from: library)
            let outfits = OutfitDefinition.decodeAll(from: library)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let weapons = WeaponDefinition.decodeAll(from: library)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let missions = MissionDefinition.decodeAll(from: library)
                .sorted {
                    if $0.id != $1.id { return $0.id < $1.id }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            let resolver = MissionChainResolver(missions: missions)
            let storyFlags = StoryFlagCatalog(
                missions: missions,
                outfits: outfits,
                ships: ships,
                timedEvents: TimedEventSource.decodeAll(from: library),
                disasters: DisasterSource.decodeAll(from: library),
                characters: CharacterSource.decodeAll(from: library),
                planets: PlanetSource.decodeAll(from: library),
                systems: SystemSource.decodeAll(from: library),
                fleets: FleetSource.decodeAll(from: library),
                junkTypes: JunkTypeSource.decodeAll(from: library)
            ).flagsByID
            let names = ResourceNameIndex(library: library)

            return .success(GameDataSnapshot(
                ships: ships,
                outfits: outfits,
                weapons: weapons,
                // GameDataLibrary already keeps one resource per ID, so the
                // merge rule below never has to choose.
                shipsByID: Dictionary(ships.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                outfitsByID: Dictionary(outfits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                weaponsByID: Dictionary(weapons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                missions: missions,
                missionResolver: resolver,
                missionChains: resolver.allChains(),
                missionAnalysis: MissionDiagnostics.Prepared(missions: missions),
                storyFlags: storyFlags,
                descriptions: DescriptionText.decodeAll(from: library),
                names: names,
                galaxy: GalaxyMap(library: library),
                failedArchiveCount: library.failedArchives.count
            ))
        } catch {
            return .failure("Could not load Nova game data:\n\(error.localizedDescription)")
        }
    }
}
