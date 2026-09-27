import Foundation

// Stores the user-chosen EV Nova install folder. The Pilots and Nova Files
// folders are derived from it, so the user only has to point at the game once.
// Persisted via UserDefaults so it survives app relaunches.
public final class AppSettings: ObservableObject {
    @Published public var gameFolderPath: String? {
        didSet { UserDefaults.standard.set(gameFolderPath, forKey: Self.gameFolderPathKey) }
    }

    private static let gameFolderPathKey: String = "gameFolderPath"

    public static let pilotsFolderName: String = "Pilots"
    public static let novaFilesFolderName: String = "Nova Files"

    // Only a starting point for the folder picker; the app never assumes the
    // game is installed here.
    public static var suggestedGameFolder: String {
        NSString(string: "~/Desktop/EV Nova").expandingTildeInPath
    }

    public init() {
        self.gameFolderPath = UserDefaults.standard.string(forKey: Self.gameFolderPathKey)
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
