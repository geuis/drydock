import SwiftUI

@main
struct EVNPilotEditorApp: App {
    // Asks before quitting with unsaved pilot edits.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var settings: AppSettings
    @StateObject private var schema: FieldSchema
    @StateObject private var gameData: GameDataStore
    @StateObject private var navigator: AppNavigator = AppNavigator()

    init() {
        // Always dark, whatever the system setting. Set app-wide rather than
        // per view so AppKit-drawn controls, sheets, alerts, and the
        // Settings window all match (per-view preferredColorScheme left some
        // sidebar text dark-on-dark).
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)

        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _schema = StateObject(wrappedValue: FieldSchema.loadDefault())
        // Skip loading entirely until the user has picked a real install; the
        // prompt triggers the load once they do.
        let novaFilesURL: URL? = settings.hasValidGameFolder ? settings.novaFilesFolderURL : nil
        _gameData = StateObject(wrappedValue: GameDataStore(directoryURL: novaFilesURL))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(schema)
                .environmentObject(gameData)
                .environmentObject(navigator)
                .frame(minWidth: 700, minHeight: 500)
                .background(FillScreenOnOpen())
        }
        // Story Chains needs room for the chain list plus mission details.
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}

// Shows the install-folder prompt until a valid EV Nova folder is known, then
// the main tabs. Lives in a view (not the App) so it observes settings changes.
private struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var gameData: GameDataStore
    @EnvironmentObject private var navigator: AppNavigator

    // One per window, so closing a window only asks about its own pilot.
    @StateObject private var unsavedChanges: UnsavedChangesTracker = UnsavedChangesTracker()

    var body: some View {
        Group {
            if settings.hasValidGameFolder {
                mainTabs
            } else {
                GameFolderPromptView()
            }
        }
        .environmentObject(unsavedChanges)
        .background(WindowCloseGuard(tracker: unsavedChanges))
        .onChange(of: settings.gameFolderPath) { _, _ in
            let novaFilesURL: URL? = settings.hasValidGameFolder ? settings.novaFilesFolderURL : nil
            gameData.reload(directoryURL: novaFilesURL)
        }
    }

    private var mainTabs: some View {
        TabView(selection: $navigator.tab) {
            PilotWorkspaceView()
                .tabItem {
                    Label("Pilots", systemImage: "person.crop.circle")
                }
                .tag(AppNavigator.Tab.pilots)

            GameDataView()
                .tabItem {
                    Label("Game Data", systemImage: "cylinder.split.1x2")
                }
                .tag(AppNavigator.Tab.gameData)

            GalaxyMapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(AppNavigator.Tab.map)
        }
        .task {
            gameData.loadOnce()
        }
    }
}
