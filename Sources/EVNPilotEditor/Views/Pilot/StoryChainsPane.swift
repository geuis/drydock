import SwiftUI

// Story chains evaluated against the open pilot. Answers "why isn't this
// mission showing up?" by marking each mission's state, listing the unmet
// conditions and conflicts, and letting the user flip the flags involved.
struct StoryChainsPane: View {
    @ObservedObject var pilotFile: PilotFile
    @Binding var focusedMissionID: Int?

    @EnvironmentObject private var gameData: GameDataStore
    @EnvironmentObject private var navigator: AppNavigator

    private enum BrowseMode: String, CaseIterable, Identifiable {
        case chains = "Chains"
        case missions = "All Missions"

        var id: String { rawValue }
    }

    private enum ChainFilter: String, CaseIterable, Identifiable {
        case needsAttention = "Needs Attention"
        case started = "Started"
        case all = "All"

        var id: String { rawValue }
    }

    @State private var browseMode: BrowseMode = .chains
    @State private var chainFilter: ChainFilter = .needsAttention
    @State private var statusFilter: MissionStatus?
    @State private var searchText: String = ""
    @State private var selectedChainID: Int?
    @State private var selectedMissionID: Int?
    // The mission picked in the chain graph, shown in the pane below it.
    @State private var chainMissionID: Int?
    // nil until the handle is first dragged, then a third of the height.
    @State private var detailPaneHeight: CGFloat?
    @State private var detailHeightAtDragStart: CGFloat?
    @State private var diagnostics: MissionDiagnostics?
    @State private var diagnosedState: PilotStoryState?
    // Goes up every time the pilot is re-evaluated, even when nothing
    // changed, so a control can tell its edit has been checked.
    @State private var evaluationCount: Int = 0

    var body: some View {
        Group {
            if let snapshot = gameData.snapshot {
                HSplitView {
                    browser(snapshot)
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)

                    detail(snapshot)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if gameData.isLoading {
                ProgressView("Loading game data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Game Data Unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(gameData.errorMessage ?? "Set the Nova Files folder in Settings, then restart the app.")
                )
            }
        }
        .onChange(of: pilotFile.workingBytes, initial: true) { _, _ in
            recompute()
        }
        .onChange(of: gameData.isLoading) { _, _ in
            recompute()
            focus(on: focusedMissionID)
        }
        .onChange(of: focusedMissionID, initial: true) { _, newValue in
            focus(on: newValue)
        }
    }

    // MARK: - Browser (left column)

    private func browser(_ snapshot: GameDataSnapshot) -> some View {
        VStack(spacing: 8) {
            Picker("Browse", selection: $browseMode) {
                ForEach(BrowseMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if browseMode == .chains {
                Picker("Show", selection: $chainFilter) {
                    ForEach(ChainFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } else {
                Picker("Status", selection: $statusFilter) {
                    Text("Any Status").tag(MissionStatus?.none)

                    ForEach(MissionStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(MissionStatus?.some(status))
                    }
                }
                .labelsHidden()
            }

            TextField("Search missions by name or ID", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if browseMode == .chains {
                chainLegend
                chainList(snapshot)
            } else {
                missionList(snapshot)
            }
        }
        .padding(8)
    }

    // The chain rows show bare icons with counts, so name them once here.
    private var chainLegend: some View {
        // Two rows so it fits the narrow browser column without wrapping words.
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                legendLabel(MissionStatus.active.displayName, symbol: MissionStatus.active.symbolName, color: MissionStatus.active.color)
                legendLabel(MissionStatus.blocked.displayName, symbol: MissionStatus.blocked.symbolName, color: MissionStatus.blocked.color)
            }

            GridRow {
                legendLabel(MissionStatus.impossible.displayName, symbol: MissionStatus.impossible.symbolName, color: MissionStatus.impossible.color)
                legendLabel("Conflict", symbol: "arrow.triangle.branch", color: .orange)
            }
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendLabel(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    private func chainList(_ snapshot: GameDataSnapshot) -> some View {
        let rows: [(chain: MissionChainComponent, summary: ChainSummary)] = filteredChains(snapshot)

        return List(rows, id: \.chain.id, selection: $selectedChainID) { row in
            VStack(alignment: .leading, spacing: 4) {
                Text(chainTitle(row.chain))
                    .lineLimit(2)

                if let storyline = storylineLabel(row.chain) {
                    Text(storyline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text("\(row.chain.missions.count) missions")
                        .foregroundStyle(.secondary)

                    ForEach([MissionStatus.active, .blocked, .impossible], id: \.self) { status in
                        if let count = row.summary.counts[status], count > 0 {
                            Label("\(count)", systemImage: status.symbolName)
                                .foregroundStyle(status.color)
                                .help("\(count) \(status.displayName)")
                        }
                    }

                    if row.summary.conflictCount > 0 {
                        Label("\(row.summary.conflictCount)", systemImage: "arrow.triangle.branch")
                            .foregroundStyle(.orange)
                            .help("Conflicting branches")
                    }

                    if let lock = storyLock(row.summary.firstBlockedMissionIDs) {
                        Label("Locked out", systemImage: "lock.fill")
                            .foregroundStyle(.orange)
                            .help(lock.issue.title)
                    }
                }
                .font(.caption)
            }
            .padding(.vertical, 2)
            .tag(row.chain.id)
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    chainFilter == .needsAttention ? "Nothing Stuck" : "No Chains",
                    systemImage: "checkmark.circle",
                    description: Text(chainFilter == .needsAttention ? "No started story chain is stuck or conflicted, and no storyline is locked out by something you did elsewhere." : "No chains match.")
                )
            }
        }
        .onChange(of: selectedChainID) { _, _ in
            selectedMissionID = nil
        }
    }

    private func missionList(_ snapshot: GameDataSnapshot) -> some View {
        let missions: [MissionDefinition] = filteredMissions(snapshot)

        return List(missions, id: \.id, selection: $selectedMissionID) { mission in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(GameName(mission.name).title)
                        .lineLimit(1)

                    Text("ID \(mission.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let status = diagnostics?.diagnosis(for: mission.id)?.status {
                    MissionStatusBadge(status: status)
                }
            }
            .tag(mission.id)
        }
        .onChange(of: selectedMissionID) { _, _ in
            selectedChainID = nil
        }
    }

    // MARK: - Detail (right column)

    @ViewBuilder
    private func detail(_ snapshot: GameDataSnapshot) -> some View {
        if browseMode == .missions, let missionID = selectedMissionID, let mission = snapshot.missionResolver.mission(id: missionID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MissionHeader(mission: mission, diagnosis: diagnostics?.diagnosis(for: missionID)) {
                        findOnMap(mission, snapshot: snapshot)
                    }

                    completionControl(mission, snapshot: snapshot)

                    MissionDiagnosisView(
                        mission: mission,
                        diagnosis: diagnostics?.diagnosis(for: missionID),
                        pilotFile: pilotFile,
                        snapshot: snapshot,
                        onSelectMission: select
                    )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let chainID = selectedChainID, let chain = snapshot.missionChains.first(where: { $0.id == chainID }) {
            chainDetail(chain, snapshot: snapshot)
        } else {
            ContentUnavailableView(
                "Choose a Story Chain",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("Pick a chain on the left to see which missions are done, which are available, and what's blocking the rest.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Summary on top, the chain as a flowchart in the middle, and the
    // picked mission's details in a pane across the bottom. The pane's
    // height only changes when its handle is dragged; a VSplitView resized
    // it to fit each newly picked mission's content.
    private func chainDetail(_ chain: MissionChainComponent, snapshot: GameDataSnapshot) -> some View {
        GeometryReader { geometry in
            let total: CGFloat = geometry.size.height
            let paneHeight: CGFloat = clampedDetailHeight(detailPaneHeight ?? total / 3, total: total)

            VStack(spacing: 0) {
                chainHeader(chain, snapshot: snapshot)

                Divider()

                MissionChainGraphView(
                    chain: chain,
                    snapshot: snapshot,
                    diagnostics: diagnostics,
                    stuckMissionIDs: Set(diagnostics?.summary(for: chain, resolver: snapshot.missionResolver).firstBlockedMissionIDs ?? []),
                    selectedMissionID: $chainMissionID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                detailPaneHandle(paneHeight: paneHeight, total: total)

                chainMissionDetail(chain, snapshot: snapshot)
                    .frame(maxWidth: .infinity)
                    .frame(height: paneHeight)
            }
            .frame(width: geometry.size.width, height: total)
        }
    }

    private func findOnMap(_ mission: MissionDefinition, snapshot: GameDataSnapshot) {
        navigator.showOnMap(MapFocus(
            missionID: mission.id,
            title: GameName(mission.name).title,
            locations: MissionMapLocations.locations(for: mission, galaxy: snapshot.galaxy, names: snapshot.names)
        ))
    }

    // Identity per mission, so the last change's message (and which text
    // parts are open) doesn't carry over to the next mission picked.
    private func completionControl(_ mission: MissionDefinition, snapshot: GameDataSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MissionCompletionControl(
                mission: mission,
                status: diagnostics?.diagnosis(for: mission.id)?.status,
                evaluationCount: evaluationCount,
                pilotFile: pilotFile,
                storyFlags: snapshot.storyFlags
            )

            MissionTextView(
                mission: mission,
                descriptions: snapshot.descriptions,
                pilotFile: pilotFile
            )
        }
        .id(mission.id)
    }

    // Leaves room for the chart and keeps the details pane usable.
    private func clampedDetailHeight(_ height: CGFloat, total: CGFloat) -> CGFloat {
        let minimum: CGFloat = 140
        let maximum: CGFloat = max(minimum, total - 280)

        return min(max(height, minimum), maximum)
    }

    private func detailPaneHandle(paneHeight: CGFloat, total: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start: CGFloat = detailHeightAtDragStart ?? paneHeight

                        if detailHeightAtDragStart == nil {
                            detailHeightAtDragStart = paneHeight
                        }

                        // Dragging up makes the pane taller.
                        detailPaneHeight = clampedDetailHeight(start - value.translation.height, total: total)
                    }
                    .onEnded { _ in
                        detailHeightAtDragStart = nil
                    }
            )
    }

    private func chainHeader(_ chain: MissionChainComponent, snapshot: GameDataSnapshot) -> some View {
        let summary: ChainSummary? = diagnostics?.summary(for: chain, resolver: snapshot.missionResolver)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(chainTitle(chain))
                    .font(.title3.weight(.semibold))

                if let storyline = storylineLabel(chain) {
                    Text("Storyline: \(storyline)")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                ForEach(MissionStatus.allCases, id: \.self) { status in
                    if let count = summary?.counts[status], count > 0 {
                        Label("\(count) \(status.displayName)", systemImage: status.symbolName)
                            .foregroundStyle(status.color)
                    }
                }
            }

            if let stuck = summary?.firstBlockedMissionIDs, !stuck.isEmpty {
                Text("Stuck at: " + stuck.map { missionTitle($0, snapshot: snapshot) }.joined(separator: ", "))
                    .foregroundStyle(.orange)

                // The top reason for each stuck point, so "why can't I start
                // this storyline" is answered without clicking anything.
                ForEach(stuckReasons(stuck, snapshot: snapshot), id: \.self) { reason in
                    Label(reason, systemImage: "arrow.turn.down.right")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // A lock is held by another storyline; jump straight to it.
                if let lock = storyLock(stuck), let holderID = lock.issue.relatedMissionIDs.first, !chain.missions.contains(where: { $0.id == holderID }) {
                    Button("Go to \(missionTitle(holderID, snapshot: snapshot)), which holds the lock") {
                        select(holderID)
                    }
                    .buttonStyle(.link)
                }
            }

            if let conflicts = summary?.conflictCount, conflicts > 0 {
                Text("\(conflicts) conflicting branch\(conflicts == 1 ? "" : "es"): finishing one mission can lock another out.")
                    .foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chainMissionDetail(_ chain: MissionChainComponent, snapshot: GameDataSnapshot) -> some View {
        if let missionID = chainMissionID, let mission = chain.missions.first(where: { $0.id == missionID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MissionHeader(mission: mission, diagnosis: diagnostics?.diagnosis(for: missionID)) {
                        findOnMap(mission, snapshot: snapshot)
                    }

                    completionControl(mission, snapshot: snapshot)

                    MissionDiagnosisView(
                        mission: mission,
                        diagnosis: diagnostics?.diagnosis(for: missionID),
                        pilotFile: pilotFile,
                        snapshot: snapshot,
                        onSelectMission: select
                    )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Click a Mission",
                systemImage: "cursorarrow.click",
                description: Text("Click a box in the chart to see whether it's available, what it needs, and what it leads to.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Filtering

    private func filteredChains(_ snapshot: GameDataSnapshot) -> [(chain: MissionChainComponent, summary: ChainSummary)] {
        let query: String = searchText.trimmingCharacters(in: .whitespaces)

        return snapshot.missionChains.compactMap { chain in
            guard let diagnostics else { return nil }

            let summary: ChainSummary = diagnostics.summary(for: chain, resolver: snapshot.missionResolver)
            let started: Bool = (summary.counts[.active] ?? 0) + (summary.counts[.completed] ?? 0) > 0

            switch chainFilter {
            case .needsAttention:
                // Also include storylines you haven't started because
                // something you did elsewhere locks their first mission.
                let lockedOut: Bool = summary.firstBlockedMissionIDs.contains { missionID in
                    diagnostics.diagnosis(for: missionID)?.issues.contains { $0.id.hasPrefix("lock-") } ?? false
                }
                let stuckOrConflicted: Bool = !summary.firstBlockedMissionIDs.isEmpty || summary.conflictCount > 0

                guard (started && stuckOrConflicted) || lockedOut else { return nil }

            case .started:
                guard started else { return nil }

            case .all:
                break
            }

            if !query.isEmpty {
                let matches: Bool = chain.missions.contains { mission in
                    mission.name.localizedCaseInsensitiveContains(query) || String(mission.id) == query
                }

                guard matches else { return nil }
            }

            return (chain, summary)
        }
    }

    private func filteredMissions(_ snapshot: GameDataSnapshot) -> [MissionDefinition] {
        let query: String = searchText.trimmingCharacters(in: .whitespaces)

        return snapshot.missions.filter { mission in
            if let statusFilter, diagnostics?.diagnosis(for: mission.id)?.status != statusFilter {
                return false
            }

            guard !query.isEmpty else { return true }
            return mission.name.localizedCaseInsensitiveContains(query) || String(mission.id) == query
        }
    }

    // MARK: - Navigation

    // Jumps to a mission from elsewhere (the Current Missions page or a
    // related-mission link), opening its chain with the mission expanded.
    private func focus(on missionID: Int?) {
        guard let missionID else { return }

        // Keep the request pending until game data has loaded; the
        // isLoading change handler calls this again.
        guard gameData.snapshot != nil else { return }

        select(missionID)
        focusedMissionID = nil
    }

    private func select(_ missionID: Int) {
        guard let snapshot = gameData.snapshot else { return }

        if let chain = snapshot.missionChains.first(where: { chain in chain.missions.contains { $0.id == missionID } }) {
            browseMode = .chains
            chainFilter = .all
            searchText = ""
            selectedChainID = chain.id
            chainMissionID = missionID
        } else {
            browseMode = .missions
            statusFilter = nil
            searchText = ""
            selectedMissionID = missionID
        }
    }

    // MARK: - Evaluation

    private func recompute() {
        defer { evaluationCount += 1 }

        guard let snapshot = gameData.snapshot else {
            diagnostics = nil
            return
        }

        let bytes: Data = pilotFile.workingBytes
        let activeIDs: Set<Int> = Set(pilotFile.missionSlots.filter(\.isActive).compactMap(\.missionID))
        let state: PilotStoryState = PilotStoryState(
            bits: MissionBits.decodeAll(from: bytes),
            outfitCounts: PilotInventory.decodeItemCount(from: bytes),
            exploration: PilotExploration.decodeExploration(from: bytes),
            combatRating: pilotFile.combatRating,
            isMale: pilotFile.isMale,
            activeMissionIDs: activeIDs,
            ship: PilotShipState(pilotBytes: bytes, shipsByID: snapshot.shipsByID, outfitsByID: snapshot.outfitsByID)
        )

        // Most edits (credits, names, escorts) don't change anything a
        // mission's availability depends on, so skip the rebuild.
        guard diagnostics == nil || state != diagnosedState else { return }

        diagnosedState = state
        diagnostics = MissionDiagnostics(prepared: snapshot.missionAnalysis, storyFlags: snapshot.storyFlags, state: state)
    }

    // MARK: - Titles

    private func chainTitle(_ chain: MissionChainComponent) -> String {
        let rootID: Int? = chain.rootMissionIDs.first ?? chain.missions.first?.id
        let root: MissionDefinition? = chain.missions.first { $0.id == rootID }
        let title: String = root.map { GameName($0.name).title } ?? "Chain \(chain.id)"
        return chain.isCyclic ? "\(title) (loops)" : title
    }

    // Chains are named after their first mission, which rarely says which
    // storyline they belong to. The scenario's own mission names usually
    // carry a tag after the ";" (e.g. "Vellos3", "Rebel II14"), so the most
    // common tags across the chain name its storylines.
    private func storylineLabel(_ chain: MissionChainComponent) -> String? {
        var counts: [String: Int] = [:]

        for mission in chain.missions {
            guard let tag = MissionStoryline.tag(ofNote: GameName(mission.name).note) else { continue }
            counts[tag, default: 0] += 1
        }

        let ranked: [String] = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)

        guard !ranked.isEmpty else { return nil }
        return ranked.prefix(3).joined(separator: ", ")
    }

    // The story lock stopping the first stuck mission that has one. Its
    // first related mission is the one most likely holding the lock.
    private func storyLock(_ stuckMissionIDs: [Int]) -> (missionID: Int, issue: MissionIssue)? {
        for missionID in stuckMissionIDs {
            if let issue = diagnostics?.diagnosis(for: missionID)?.issues.first(where: { $0.id.hasPrefix("lock-") }) {
                return (missionID, issue)
            }
        }

        return nil
    }

    // One line per distinct top blocker. Stuck points often share a cause
    // (Polaris 1 and its Vell-os variant are both locked by Wild Geese).
    private func stuckReasons(_ missionIDs: [Int], snapshot: GameDataSnapshot) -> [String] {
        var reasons: [String] = []

        for missionID in missionIDs {
            let issues: [MissionIssue] = diagnostics?.diagnosis(for: missionID)?.issues ?? []
            guard let issue = issues.first(where: { $0.id.hasPrefix("lock-") }) ?? issues.first(where: { $0.severity == .blocker }) else { continue }

            let reason: String = "\(missionTitle(missionID, snapshot: snapshot)): \(issue.title)"
            let alreadyCovered: Bool = reasons.contains { $0.hasSuffix(": \(issue.title)") }

            if !alreadyCovered {
                reasons.append(reason)
            }
        }

        return reasons
    }

    // With the ID, since chains often reuse a name (Polaris 1 and its
    // Vell-os variant are both "Transport Mu'Randa").
    private func missionTitle(_ missionID: Int, snapshot: GameDataSnapshot) -> String {
        let title: String = snapshot.missionResolver.mission(id: missionID).map { GameName($0.name).title } ?? "Mission"
        return "\(title) #\(missionID)"
    }
}

// MARK: - Header

private struct MissionHeader: View {
    let mission: MissionDefinition
    let diagnosis: MissionDiagnosis?
    let onFindOnMap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(GameName(mission.name).full)
                .font(.title3.weight(.semibold))

            HStack {
                Text("Mission \(mission.id)")
                    .foregroundStyle(.secondary)

                if let status = diagnosis?.status {
                    MissionStatusBadge(status: status)
                }

                Spacer()

                Button {
                    onFindOnMap()
                } label: {
                    Label("Find on Map", systemImage: "map")
                }
                .help("Show where this mission is offered and where it sends you")
            }
        }
    }
}

// MARK: - Mission links

enum MissionLinks {
    // How `mission` starts `targetID`, in words ("completed", "refused"...).
    static func triggerLabel(from mission: MissionDefinition, to targetID: Int, resolver: MissionChainResolver) -> String {
        var labels: [String] = []

        if mission.successMissionIDs.contains(targetID) {
            labels.append("completed")
        } else if let flagID = resolver.unlockFlag(from: mission, to: targetID) {
            // Unlocked rather than started: success turns on a flag the
            // target waits for.
            labels.append("completed, via story flag \(flagID)")
        }

        if mission.acceptMissionIDs.contains(targetID) { labels.append("accepted") }
        if mission.refuseMissionIDs.contains(targetID) { labels.append("refused") }
        if mission.failureMissionIDs.contains(targetID) { labels.append("failed") }
        if mission.abortMissionIDs.contains(targetID) { labels.append("aborted") }
        if mission.shipDoneMissionIDs.contains(targetID) { labels.append("ship objective done") }

        return labels.isEmpty ? "" : "(" + labels.joined(separator: " / ") + ")"
    }
}
