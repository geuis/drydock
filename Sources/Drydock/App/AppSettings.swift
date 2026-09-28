import Foundation

// Stores the user-chosen EV Nova install folder. The Pilots and Nova Files
// folders are derived from it, so the user only has to point at the game once.
// Persisted via UserDefaults so it survives app relaunches.
public final class AppSettings: ObservableObject {
    @Published public var gameFolderPath: String? {
        didSet { UserDefaults.standard.set(gameFolderPath, forKey: Self.gameFolderPathKey) }
    }

    @Published public var checksForUpdatesAutomatically: Bool {
        didSet { UserDefaults.standard.set(checksForUpdatesAutomatically, forKey: Self.checksForUpdatesKey) }
    }

    private static let gameFolderPathKey: String = "gameFolderPath"
    private static let checksForUpdatesKey: String = "checksForUpdatesAutomatically"

    // Read directly at launch, before any settings object exists. Defaults to
    // on so fixes reach people who never open Settings.
    public static var storedChecksForUpdatesAutomatically: Bool {
        UserDefaults.standard.object(forKey: checksForUpdatesKey) as? Bool ?? true
    }

    public static let pilotsFolderName: String = "Pilots"
    public static let novaFilesFolderName: String = "Nova Files"
    public static let pluginsFolderName: String = "Nova Plug-ins"

    public init() {
        self.gameFolderPath = UserDefaults.standard.string(forKey: Self.gameFolderPathKey)
        self.checksForUpdatesAutomatically = Self.storedChecksForUpdatesAutomatically
    }

    public var gameFolderURL: URL? {
        guard let gameFolderPath else { return nil }

        return URL(fileURLWithPath: gameFolderPath, isDirectory: true)
    }

    public var pilotsFolderURL: URL? {
        gameFolderURL?.appendingPathComponent(Self.pilotsFolderName, isDirectory: true)
    }

    public var novaFilesFolderURL: URL? {
        gameFolderURL?.appendingPathComponent(Self.novaFilesFolderName, isDirectory: true)
    }

    public var pluginsFolderURL: URL? {
        gameFolderURL?.appendingPathComponent(Self.pluginsFolderName, isDirectory: true)
    }

    // True once a folder is saved and it still looks like an EV Nova install,
    // so a moved or deleted game sends the user back to the prompt.
    public var hasValidGameFolder: Bool {
        guard let gameFolderURL else { return false }

        return Self.isGameFolder(gameFolderURL)
    }

    // A Pilots folder only appears after the first pilot is created, so the
    // Nova Files folder is the reliable sign of an install.
    public static func isGameFolder(_ url: URL) -> Bool {
        let novaFilesURL: URL = url.appendingPathComponent(novaFilesFolderName, isDirectory: true)
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: novaFilesURL.path, isDirectory: &isDirectory)

        return exists && isDirectory.boolValue
    }
}
