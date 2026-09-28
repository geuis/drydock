import SwiftUI

// Lets the user change which EV Nova install the app reads. The Pilots and
// Nova Files folders are derived from it, so they are shown but not editable.
public struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var rejectedFolderPath: String?

    public init() {}

    public var body: some View {
        Form {
            Section {
                Text(settings.gameFolderPath ?? "Not chosen yet")
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)

                Button("Choose Folder...") {
                    chooseGameFolder()
                }

                if let rejectedFolderPath {
                    Text("That folder doesn't contain a \"\(AppSettings.novaFilesFolderName)\" folder:\n\(rejectedFolderPath)")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("EV Nova Folder")
            }

            Section("Derived Folders") {
                LabeledContent("Pilots", value: settings.pilotsFolderURL?.path ?? "-")
                    .textSelection(.enabled)

                LabeledContent("Nova Files", value: settings.novaFilesFolderURL?.path ?? "-")
                    .textSelection(.enabled)

                LabeledContent("Plug-ins", value: settings.pluginsFolderURL?.path ?? "-")
                    .textSelection(.enabled)
            }

            Section("Updates") {
                LabeledContent("Version", value: UpdateChecker.currentVersion?.description ?? "Development build")

                Toggle("Check for updates when Drydock starts", isOn: $settings.checksForUpdatesAutomatically)

                Button("Check Now") {
                    UpdateChecker.shared.checkFromMenu()
                }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 380)
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
