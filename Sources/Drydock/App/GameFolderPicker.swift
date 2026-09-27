import AppKit

// One place for the "where is EV Nova installed" panel, shared by the
// first-launch prompt and Settings so both explain the choice the same way.
@MainActor
public enum GameFolderPicker {
    public static func choose(startingAt startPath: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder EV Nova is installed in (the one that contains \"\(AppSettings.novaFilesFolderName)\" and \"\(AppSettings.pilotsFolderName)\")."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: startPath ?? AppSettings.suggestedGameFolder, isDirectory: true)

        guard panel.runModal() == .OK else { return nil }

        return panel.url
    }
}
