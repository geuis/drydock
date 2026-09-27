import SwiftUI
import Combine

// The editable areas of a pilot, in the order they appear in the sidebar.
enum PilotSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case shipAndOutfits
    case escorts
    case missions
    case storyChains
    case storyFlags
    case galaxy
    case characters
    case universe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Pilot & Ship"
        case .shipAndOutfits: return "Outfits & Weapons"
        case .escorts: return "Escorts & Fighters"
        case .missions: return "Current Missions"
        case .storyChains: return "Story Chains"
        case .storyFlags: return "Story Flags"
        case .galaxy: return "Systems & Planets"
        case .characters: return "Characters"
        case .universe: return "Ranks, Events & Prices"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "person.crop.circle"
        case .shipAndOutfits: return "shippingbox"
        case .escorts: return "airplane"
        case .missions: return "list.bullet.clipboard"
        case .storyChains: return "point.3.connected.trianglepath.dotted"
        case .storyFlags: return "flag"
        case .galaxy: return "globe"
        case .characters: return "person.2"
        case .universe: return "rosette"
        }
    }
}

// Owns the currently open pilot file and re-publishes its changes, so views
// that only know about the session (toolbar, sidebar) still refresh when an
// edit marks the file dirty.
@MainActor
final class PilotSession: ObservableObject {
    @Published private(set) var pilotFile: PilotFile?

    private var fileObserver: AnyCancellable?

    func open(_ url: URL) throws {
        let file: PilotFile = try PilotFile(url: url)
        attach(file)
    }

    // Reloads from disk, discarding every unsaved edit.
    func revert() throws {
        guard let url = pilotFile?.url else { return }
        try open(url)
    }

    func close() {
        fileObserver = nil
        pilotFile = nil
    }

    private func attach(_ file: PilotFile) {
        fileObserver = file.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        pilotFile = file
    }
}

// Root of the Pilots tab: pick a pilot, then pick what to edit.
public struct PilotWorkspaceView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var schema: FieldSchema
    @EnvironmentObject private var gameData: GameDataStore
    @EnvironmentObject private var navigator: AppNavigator

    @StateObject private var session: PilotSession = PilotSession()

    @State private var pilotURLs: [URL] = []
    @State private var folderMessage: String?
    @State private var section: PilotSection? = .overview
    @State private var focusedMissionID: Int?

    @State private var pendingPilotURL: URL?
    @State private var showingDiscardForSwitch = false
    @State private var showingSaveConfirmation = false
    @State private var gameWasRunningAtSave = false
    @State private var showingChangedOnDisk = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detail
        }
        .navigationTitle(windowTitle)
        .navigationSubtitle(isDirty ? "Unsaved changes" : "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Text rather than an icon, so it's obvious edits aren't
                // written until this is pressed.
                Button("Save Pilot Changes") {
                    // Checked here, not in the alert text, because the alert
                    // message is rebuilt on every redraw of the window.
                    gameWasRunningAtSave = PilotFile.isGameRunning()
                    showingSaveConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .help("Write changes to the pilot file (a backup is made first)")
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)
            }
        }
        .onAppear {
            refreshPilotList()
        }
        .onChange(of: settings.gameFolderPath) { _, _ in
            refreshPilotList()
        }
        .onChange(of: pilotLocation, initial: true) { _, newLocation in
            navigator.pilotLocation = newLocation
        }
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: $showingDiscardForSwitch,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                if let pendingPilotURL {
                    open(pendingPilotURL)
                }
                pendingPilotURL = nil
            }

            Button("Cancel", role: .cancel) {
                pendingPilotURL = nil
            }
        } message: {
            Text("The current pilot has edits that haven't been saved.")
        }
        .alert("Save Pilot File?", isPresented: $showingSaveConfirmation) {
            Button("Save") {
                save()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(saveMessage)
        }
        .confirmationDialog(
            "The pilot file changed on disk",
            isPresented: $showingChangedOnDisk,
            titleVisibility: .visible
        ) {
            Button("Overwrite With My Changes", role: .destructive) {
                save(overwritingExternalChanges: true)
            }

            Button("Reload From Disk (Discard My Changes)") {
                revert()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Something else, usually EV Nova, saved this pilot after you opened it. Overwriting replaces that newer progress with your edited copy; a backup of the version on disk is made first. Reloading keeps the newer progress but drops your unsaved edits.")
        }
        .editErrorAlert($errorMessage)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            Section("Pilot") {
                if let folderMessage {
                    Text(folderMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    pilotList
                }

                Button {
                    refreshPilotList()
                } label: {
                    Label("Refresh Pilot List", systemImage: "arrow.clockwise")
                }
                // A borderless button in the sidebar drew its title in
                // near-black, unreadable on the dark background.
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .font(.caption)
            }

            if session.pilotFile != nil {
                Section("Edit") {
                    ForEach(PilotSection.allCases) { item in
                        Label(item.title, systemImage: item.symbolName)
                            .tag(item)
                    }
                }
            }

            if gameData.isLoading {
                Section {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading game data…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let message = gameData.errorMessage {
                Section("Game Data") {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static let pilotRowHeight: CGFloat = 26
    private static let visiblePilotRows: Int = 5

    // Up to five pilots show at once; more scroll. A plain list of buttons
    // rather than a nested List, which can't sit inside the sidebar List.
    private var pilotList: some View {
        let rowCount: Int = min(max(pilotURLs.count, 1), Self.visiblePilotRows)

        return ScrollView {
            VStack(spacing: 0) {
                ForEach(pilotURLs, id: \.self) { url in
                    pilotRow(url)
                }
            }
            .padding(Self.pilotListInset)
        }
        .frame(height: CGFloat(rowCount) * Self.pilotRowHeight + Self.pilotListInset * 2)
        // A faint outline so the list reads as one control against the
        // sidebar; the system separator colour suits the dark theme.
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private static let pilotListInset: CGFloat = 3

    private func pilotRow(_ url: URL) -> some View {
        let isOpen: Bool = url == session.pilotFile?.url

        return HStack(spacing: 6) {
            Button {
                guard !isOpen else { return }
                requestOpen(url)
            } label: {
                Text(url.deletingPathExtension().lastPathComponent)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            // Plain style with an explicit colour; the default drew
            // near-black text on the dark sidebar.
            .buttonStyle(.plain)
            .foregroundStyle(isOpen ? Color.white : Color.primary)

            Button {
                requestOpen(url)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(isOpen ? Color.white : Color.secondary)
            .help("Reload pilot file: read it again from disk, e.g. after the game saved it")
            .accessibilityLabel("Reload pilot file")
        }
        .padding(.horizontal, 6)
        .frame(height: Self.pilotRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isOpen ? Color.accentColor : Color.clear)
        )
    }

    // Opens (or re-reads) a pilot from disk. With unsaved edits it asks
    // first instead of silently throwing them away.
    private func requestOpen(_ url: URL) {
        if isDirty {
            pendingPilotURL = url
            showingDiscardForSwitch = true
        } else {
            open(url)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if session.pilotFile != nil && gameData.isLoading {
            // Every section labels its rows with game data names; showing
            // them before loading finishes would read as "not in the game".
            ProgressView("Loading game data…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let pilotFile = session.pilotFile {
            switch section ?? .overview {
            case .overview:
                OverviewPane(pilotFile: pilotFile)

            case .shipAndOutfits:
                OutfitsWeaponsPane(pilotFile: pilotFile)

            case .escorts:
                EscortsPane(pilotFile: pilotFile)

            case .missions:
                CurrentMissionsPane(pilotFile: pilotFile) { missionID in
                    focusedMissionID = missionID
                    section = .storyChains
                }

            case .storyChains:
                StoryChainsPane(pilotFile: pilotFile, focusedMissionID: $focusedMissionID)

            case .storyFlags:
                StoryFlagsPane(pilotFile: pilotFile)

            case .galaxy:
                GalaxyPane(pilotFile: pilotFile)

            case .characters:
                CharactersPane(pilotFile: pilotFile)

            case .universe:
                UniversePane(pilotFile: pilotFile)
            }
        } else {
            ContentUnavailableView(
                "No Pilot Selected",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Choose a pilot from the list on the left.")
            )
        }
    }

    // MARK: - Actions

    private var isDirty: Bool {
        session.pilotFile?.isDirty ?? false
    }

    // Recomputed on every change to the pilot, so a location edited on the
    // Pilot & Ship page moves the map marker too.
    private var pilotLocation: PilotLocation? {
        guard let pilotFile = session.pilotFile, let index = pilotFile.schemaInt("lastStellar", in: schema) else { return nil }

        return PilotLocation(pilotName: pilotFile.url.deletingPathExtension().lastPathComponent, stellarID: index + 128)
    }

    private var windowTitle: String {
        guard let url = session.pilotFile?.url else { return "Pilots" }
        return url.deletingPathExtension().lastPathComponent
    }

    private var saveMessage: String {
        var message: String = "This writes to the real EV Nova save file. A backup of the original is made the first time you save in this session."

        if gameWasRunningAtSave {
            message += "\n\nEV Nova appears to be running. Quit the game first, or it may overwrite these changes."
        }

        return message
    }

    // Reading the folder happens off the main thread: the default folder is
    // on the Desktop, and macOS can hold the read while it asks for
    // permission, which would otherwise freeze the whole window.
    private func refreshPilotList() {
        guard let folderURL: URL = settings.pilotsFolderURL else {
            pilotURLs = []
            folderMessage = "Choose your EV Nova folder in Settings."
            return
        }

        folderMessage = "Reading pilots folder…"

        Task {
            let result: PilotListResult = await Task.detached(priority: .userInitiated) {
                Self.listPilots(in: folderURL)
            }.value

            switch result {
            case .found(let urls):
                pilotURLs = urls
                folderMessage = urls.isEmpty ? "No pilot files found in:\n\(folderURL.path)" : nil

            case .failed(let message):
                pilotURLs = []
                folderMessage = message
            }
        }
    }

    private enum PilotListResult: Sendable {
        case found([URL])
        case failed(String)
    }

    nonisolated private static func listPilots(in folderURL: URL) -> PilotListResult {
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failed("Pilots folder not found:\n\(folderURL.path)\nChoose it in Settings.")
        }

        do {
            let contents: [URL] = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            let pilots: [URL] = contents
                .filter { $0.pathExtension.lowercased() == "plt" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            return .found(pilots)
        } catch {
            return .failed("Could not read the pilots folder:\n\(error.localizedDescription)")
        }
    }

    private func open(_ url: URL) {
        do {
            try session.open(url)
            focusedMissionID = nil
        } catch {
            errorMessage = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func save(overwritingExternalChanges: Bool = false) {
        do {
            try session.pilotFile?.save(overwritingExternalChanges: overwritingExternalChanges)
        } catch PilotFileError.changedOnDisk {
            showingChangedOnDisk = true
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    private func revert() {
        do {
            try session.revert()
            focusedMissionID = nil
        } catch {
            errorMessage = "Could not reload the pilot: \(error.localizedDescription)"
        }
    }
}
