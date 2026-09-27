import SwiftUI

// Shown in place of the main tabs until the user points the app at a valid
// EV Nova install. Nothing else in the app works without game files.
public struct GameFolderPromptView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var rejectedFolderPath: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Where is EV Nova installed?")
                .font(.title2)

            Text("Choose your EV Nova game folder. The editor reads game data from its \"\(AppSettings.novaFilesFolderName)\" folder and your pilots from its \"\(AppSettings.pilotsFolderName)\" folder.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            if let rejectedFolderPath {
                Text("That folder doesn't contain a \"\(AppSettings.novaFilesFolderName)\" folder:\n\(rejectedFolderPath)")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 420)
            }

            Button("Choose EV Nova Folder...") {
                chooseGameFolder()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseGameFolder() {
        guard let url = GameFolderPicker.choose(startingAt: settings.gameFolderPath) else { return }

        guard AppSettings.isGameFolder(url) else {
            rejectedFolderPath = url.path
            return
        }

        rejectedFolderPath = nil
        settings.gameFolderPath = url.path
    }
}
