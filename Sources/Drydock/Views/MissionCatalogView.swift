import SwiftUI

// Standalone browser for every decoded mïsn (mission definition) resource
// found in the configured Nova Files folder - the "see complete story
// mission chains" feature. Each mission shows its own summary plus, when it
// is part of a chain, the linked missions it can lead to/from via the NCB
// "Sxxx" (start mission) tokens embedded in its control-bit expressions
// (see MissionDefinition.swift and MissionChainResolver.swift).
public struct MissionCatalogView: View {
    private enum BrowseMode: String, CaseIterable, Identifiable {
        case chains = "Chains"
        case missions = "Missions"

        var id: String { rawValue }
    }

    @EnvironmentObject private var gameData: GameDataStore
    @State private var selectedMissionID: Int?
    @State private var selectedChainID: Int?
    @State private var chainOnlyFilter = false
    @State private var browseMode: BrowseMode = .chains

    public init() {}

    private var missions: [MissionDefinition] { gameData.snapshot?.missions ?? [] }

    private var resolver: MissionChainResolver {
        gameData.snapshot?.missionResolver ?? MissionChainResolver(missions: [])
    }

    private var chains: [MissionChainComponent] { gameData.snapshot?.missionChains ?? [] }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        listContent
            .navigationTitle("Missions")
    }

    @ViewBuilder
    private var detail: some View {
        if browseMode == .chains {
            if let selectedChainID, let chain = chains.first(where: { $0.id == selectedChainID }) {
                MissionChainDetailView(chain: chain)
            } else {
                Text("Select a mission chain")
                    .foregroundStyle(.secondary)
            }
        } else {
            if let currentID = selectedMissionID, let mission = missions.first(where: { $0.id == currentID }) {
                MissionDetailView(mission: mission, resolver: resolver, missions: missions) { targetID in
                    selectedMissionID = targetID
                }
            } else {
                Text("Select a mission")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if let errorMessage = gameData.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if gameData.isLoading {
            ProgressView("Loading missions…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if missions.isEmpty {
            Text("No missions found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                Picker("Browse", selection: $browseMode) {
                    ForEach(BrowseMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)

                if browseMode == .chains {
                    chainList
                } else {
                    missionList
                }
            }
        }
    }

    private var missionList: some View {
        let resolver = self.resolver
        let visibleMissions = chainOnlyFilter
            ? missions.filter { resolver.isPartOfChain($0) }
            : missions

        return VStack(spacing: 0) {
            Toggle("Chains Only", isOn: $chainOnlyFilter)
                .padding(.horizontal)
                .padding(.bottom, 6)

            List(visibleMissions, selection: $selectedMissionID) { mission in
                missionRow(mission, showChainIcon: resolver.isPartOfChain(mission))
                    .tag(mission.id)
            }
        }
    }

    private var chainList: some View {
        List(chains, selection: $selectedChainID) { chain in
            VStack(alignment: .leading, spacing: 4) {
                Text(chainTitle(chain))
                    .font(.headline)
                HStack {
                    Text("\(chain.missions.count) missions")
                    Text("\u{00B7}")
                    Text("\(chain.edgeCount) links")
                    if chain.rootMissionIDs.count > 1 {
                        Text("\u{00B7}")
                        Text("\(chain.rootMissionIDs.count) starting points")
                    } else if chain.isCyclic {
                        Text("\u{00B7}")
                        Text("cyclic")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .tag(chain.id)
        }
        .overlay {
            if chains.isEmpty {
                Text("No linked mission chains found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func missionRow(_ mission: MissionDefinition, showChainIcon: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(mission.name)
                    .font(.headline)
                if showChainIcon {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("id \(mission.id) \u{00B7} pay \(mission.payVal)" + (mission.timeLimit > 0 ? " \u{00B7} \(mission.timeLimit)d limit" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func chainTitle(_ chain: MissionChainComponent) -> String {
        if let rootID = chain.rootMissionIDs.first,
           let root = chain.missions.first(where: { $0.id == rootID }) {
            return root.name
        }
        return chain.missions.first?.name ?? "Mission Chain"
    }

}

private struct MissionChainDetailView: View {
    let chain: MissionChainComponent

    private var missionsByID: [Int: MissionDefinition] {
        Dictionary(uniqueKeysWithValues: chain.missions.map { ($0.id, $0) })
    }

    private var title: String {
        if let rootID = chain.rootMissionIDs.first, let root = missionsByID[rootID] {
            return root.name
        }
        return chain.missions.first?.name ?? "Mission Chain"
    }

    var body: some View {
        // Built once per redraw rather than once per mission card.
        let lookup: [Int: MissionDefinition] = missionsByID

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(chain.missions.enumerated()), id: \.element.id) { index, mission in
                        MissionChainNodeCard(
                            position: index + 1,
                            mission: mission,
                            isStartingMission: chain.rootMissionIDs.contains(mission.id),
                            missionsByID: lookup
                        ) { targetID in
                            withAnimation {
                                proxy.scrollTo(targetID, anchor: .center)
                            }
                        }
                        .id(mission.id)
                    }
                }
                .padding()
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(chain.isCyclic ? "Cyclic chain" : startingMissionSummary)
                    .font(.headline)
                Text("\(chain.missions.count) missions connected by \(chain.edgeCount) trigger links")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle(title)
    }

    private var startingMissionSummary: String {
        let names = chain.rootMissionIDs.compactMap { missionsByID[$0]?.name }
        if names.count == 1 { return "Starts with \(names[0])" }
        if names.count > 1 { return "\(names.count) starting missions: \(names.joined(separator: ", "))" }
        return "Starting mission could not be determined"
    }
}

private struct MissionChainLink: Identifiable {
    let trigger: String
    let targetID: Int
    let occurrence: Int

    var id: String { "\(trigger)-\(targetID)-\(occurrence)" }
}

private struct MissionChainNodeCard: View {
    let position: Int
    let mission: MissionDefinition
    let isStartingMission: Bool
    let missionsByID: [Int: MissionDefinition]
    let onNavigate: (Int) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(position). \(mission.name)")
                        .font(.headline)
                    Spacer()
                    Text("Mission \(mission.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isStartingMission {
                    Label("Starting mission", systemImage: "play.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if links.isEmpty {
                    Label("End of this branch", systemImage: "stop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(links) { link in
                        HStack(spacing: 8) {
                            Text(link.trigger)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 92, alignment: .leading)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            if let target = missionsByID[link.targetID] {
                                Button(target.name) {
                                    onNavigate(link.targetID)
                                }
                                .buttonStyle(.link)
                            } else {
                                Text("Mission \(link.targetID) (not loaded)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var links: [MissionChainLink] {
        var result: [MissionChainLink] = []
        func append(_ trigger: String, _ ids: [Int]) {
            for (occurrence, id) in ids.enumerated() {
                result.append(MissionChainLink(trigger: trigger, targetID: id, occurrence: occurrence))
            }
        }
        append("On Success", mission.successMissionIDs)
        append("On Failure", mission.failureMissionIDs)
        append("On Accept", mission.acceptMissionIDs)
        append("On Refuse", mission.refuseMissionIDs)
        append("On Abort", mission.abortMissionIDs)
        append("Ship Done", mission.shipDoneMissionIDs)
        return result
    }
}

private struct MissionDetailView: View {
    let mission: MissionDefinition
    let resolver: MissionChainResolver
    let missions: [MissionDefinition]
    let onSelect: (Int) -> Void

    @EnvironmentObject private var gameData: GameDataStore

    var body: some View {
        Form {
            Section("Mission") {
                LabeledContent("Name", value: mission.name)
                LabeledContent("ID", value: "\(mission.id)")
                LabeledContent("Pay", value: payDescription)
                LabeledContent("Time Limit", value: mission.timeLimit > 0 ? "\(mission.timeLimit) days" : "None")
                LabeledContent("Can Abort", value: mission.canAbort ? "Yes" : "No")
            }

            Section("Availability") {
                LabeledContent("Location", value: availLocDescription)
                LabeledContent("Combat Rating", value: mission.availRating < 0 ? "None" : "\(mission.availRating)+")
                LabeledContent("Random %", value: "\(mission.availRandom)")
                if !mission.availBits.isEmpty {
                    LabeledContent("Requires", value: mission.availBits)
                }
            }

            if mission.cargoType >= 0 || mission.cargoQty > 0 {
                Section("Cargo") {
                    LabeledContent("Type", value: "\(mission.cargoType)")
                    LabeledContent("Quantity", value: "\(mission.cargoQty)")
                }
            }

            if mission.shipCount > 0 {
                Section("Special Ships") {
                    LabeledContent("Count", value: "\(mission.shipCount)")
                    LabeledContent("Goal", value: shipGoalDescription)
                }
            }

            if !mission.acceptButton.isEmpty || !mission.refuseButton.isEmpty {
                Section("Buttons") {
                    if !mission.acceptButton.isEmpty {
                        LabeledContent("Accept", value: mission.acceptButton)
                    }
                    if !mission.refuseButton.isEmpty {
                        LabeledContent("Refuse", value: mission.refuseButton)
                    }
                }
            }

            chainSection
        }
        .formStyle(.grouped)
        .navigationTitle(mission.name)
    }

    // The "see complete story mission chains" feature: shows every mission
    // this one leads to (successors, by trigger) and every mission that
    // leads to this one (predecessors), each as a tappable link, plus the
    // resolved full success-path chain when one exists.
    @ViewBuilder
    private var chainSection: some View {
        let predecessors = resolver.predecessors(of: mission)
        let successors = resolver.successors(of: mission)
        let fullChain = resolver.fullChain(containing: mission)

        if !predecessors.isEmpty || !successors.isEmpty {
            Section("Mission Chain") {
                if !predecessors.isEmpty {
                    ForEach(predecessors) { previous in
                        Button {
                            onSelect(previous.id)
                        } label: {
                            Label("Previous: \(previous.name)", systemImage: "arrow.left")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                }

                triggeredLinks(label: "On Success", ids: mission.successMissionIDs, systemImage: "arrow.right.circle")
                triggeredLinks(label: "On Failure", ids: mission.failureMissionIDs, systemImage: "xmark.circle")
                triggeredLinks(label: "On Refuse", ids: mission.refuseMissionIDs, systemImage: "hand.raised")
                triggeredLinks(label: "On Abort", ids: mission.abortMissionIDs, systemImage: "stop.circle")
                triggeredLinks(label: "On Accept", ids: mission.acceptMissionIDs, systemImage: "checkmark.circle")
                triggeredLinks(label: "On Ship Done", ids: mission.shipDoneMissionIDs, systemImage: "airplane.circle")

                if fullChain.count > 1 {
                    DisclosureGroup("Full Story Chain (\(fullChain.count) missions)") {
                        ForEach(Array(fullChain.enumerated()), id: \.element.id) { index, chainMission in
                            HStack {
                                Text("\(index + 1).")
                                    .foregroundStyle(.secondary)
                                Button(chainMission.name) {
                                    onSelect(chainMission.id)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(chainMission.id == mission.id ? Color.primary : Color.blue)
                                .fontWeight(chainMission.id == mission.id ? .semibold : .regular)
                            }
                            .padding(.leading, CGFloat(min(index, 3)) * 12)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func triggeredLinks(label: String, ids: [Int], systemImage: String) -> some View {
        ForEach(ids, id: \.self) { targetID in
            if let target = missions.first(where: { $0.id == targetID }) {
                Button {
                    onSelect(targetID)
                } label: {
                    Label("\(label): \(target.name)", systemImage: systemImage)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            } else {
                Label("\(label): mission \(targetID) (not loaded)", systemImage: systemImage)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // With government names, where the game data has them.
    private var payDescription: String {
        MissionPay(mission.payVal).description { governmentID in
            gameData.snapshot?.names.name(type: ResourceNameIndex.governments, id: governmentID).map { GameName($0).full } ?? "government \(governmentID)"
        }
    }

    private var availLocDescription: String {
        switch mission.availLoc {
        case 0: return "Mission Computer"
        case 1: return "Bar"
        case 2: return "From Ship"
        case 3: return "Spaceport"
        case 4: return "Trading"
        case 5: return "Shipyard"
        case 6: return "Outfitter"
        default: return "Unknown (\(mission.availLoc))"
        }
    }

    private var shipGoalDescription: String {
        switch mission.shipGoal {
        case -1: return "None"
        case 0: return "Destroy"
        case 1: return "Disable"
        case 2: return "Board"
        case 3: return "Escort"
        case 4: return "Observe"
        case 5: return "Rescue"
        case 6: return "Chase Off"
        default: return "Unknown (\(mission.shipGoal))"
        }
    }
}
