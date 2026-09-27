import SwiftUI

// The pilot's 16 mission slots. Each active slot is matched to its mission
// definition so it can show the real name and jump to its story chain.
struct CurrentMissionsPane: View {
    @ObservedObject var pilotFile: PilotFile
    let showInStoryChains: (Int) -> Void

    @EnvironmentObject private var gameData: GameDataStore
    @EnvironmentObject private var navigator: AppNavigator

    @State private var errorMessage: String?
    @State private var showEmptySlots = false
    @State private var slotPendingRemoval: MissionSlot?

    var body: some View {
        Form {
            Section {
                Toggle("Show empty slots", isOn: $showEmptySlots)
            } footer: {
                Text("\(activeCount) of \(MissionSlot.Layout.slotCount) mission slots are in use.")
            }

            ForEach(visibleSlots) { slot in
                slotSection(slot)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Remove this mission?",
            isPresented: Binding(
                get: { slotPendingRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        slotPendingRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Mission", role: .destructive) {
                if let slot = slotPendingRemoval {
                    perform {
                        try pilotFile.clearMissionSlot(slot.index)
                    }
                }
                slotPendingRemoval = nil
            }

            Button("Cancel", role: .cancel) {
                slotPendingRemoval = nil
            }
        } message: {
            Text("The mission is dropped without success or failure, so none of its story flags change. Use Story Flags if you need to set them yourself.")
        }
        .editErrorAlert($errorMessage)
    }

    // Uses the planets this run of the mission picked. Where it was offered
    // no longer matters once it's accepted, so that place is left out.
    private func findOnMap(_ mission: MissionDefinition, slot: MissionSlot) {
        guard let snapshot = gameData.snapshot else { return }

        let locations: [MissionMapLocation] = MissionMapLocations.locations(
            for: mission,
            galaxy: snapshot.galaxy,
            names: snapshot.names,
            chosenTravelStel: slot.travelStel,
            chosenReturnStel: slot.returnStel
        )

        navigator.showOnMap(MapFocus(
            missionID: mission.id,
            title: GameName(mission.name).title,
            locations: locations.filter { $0.role != .offered }
        ))
    }

    private var slots: [MissionSlot] {
        pilotFile.missionSlots
    }

    private var activeCount: Int {
        slots.filter(\.isActive).count
    }

    private var visibleSlots: [MissionSlot] {
        showEmptySlots ? slots : slots.filter(\.isActive)
    }

    @ViewBuilder
    private func slotSection(_ slot: MissionSlot) -> some View {
        let definition: MissionDefinition? = slot.missionID.flatMap { id in
            gameData.snapshot?.missionResolver.mission(id: id)
        }

        Section {
            if slot.isActive || !slot.missionName.isEmpty {
                // These live in the slot, apart from the numbered story
                // flags, so say which kind they are.
                Text("Mission progress flags (this slot only, not story flags)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(MissionFlagKind.allCases, id: \.self) { flag in
                    Toggle(flag.displayName, isOn: flagBinding(flag, slot: slot))
                }

                LabeledContent("Reward") {
                    HStack {
                        IntegerField(value: Int(slot.pay), range: Int(Int32.min)...Int(Int32.max), commit: { newValue in
                            try pilotFile.setMissionPay(Int32(newValue), missionIndex: slot.index)
                        }, onError: report, width: 120)

                        Text(rewardDescription(slot.pay))
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Days Left") {
                    HStack {
                        IntegerField(value: Int(slot.timeLeft), range: Int(Int16.min)...Int(Int16.max), commit: { newValue in
                            try pilotFile.setMissionTimeLeft(Int16(newValue), missionIndex: slot.index)
                        }, onError: report, width: 80)

                        if definition?.timeLimit ?? -1 <= 0 {
                            Text("No deadline")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !slot.specialShipName.isEmpty {
                    LabeledContent("Special Ship", value: slot.specialShipName)
                }

                if slot.cargoQty > 0 {
                    LabeledContent("Cargo", value: "\(slot.cargoQty) tons (type \(slot.cargoType))")
                }

                HStack {
                    if let missionID = slot.missionID {
                        Button {
                            showInStoryChains(missionID)
                        } label: {
                            Label("Show in Story Chains", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    }

                    if let definition {
                        Button {
                            findOnMap(definition, slot: slot)
                        } label: {
                            Label("Find on Map", systemImage: "map")
                        }
                        .help("Show where this mission sends you")
                    }

                    Spacer()

                    if slot.isActive {
                        Button("Remove Mission…", role: .destructive) {
                            slotPendingRemoval = slot
                        }
                    }
                }
            } else {
                Text("Empty")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text(slotTitle(slot, definition: definition))

                Spacer()

                if let missionID = slot.missionID, slot.isActive {
                    Text("Mission \(missionID)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func slotTitle(_ slot: MissionSlot, definition: MissionDefinition?) -> String {
        if let definition {
            return GameName(definition.name).full
        }

        if !slot.missionName.isEmpty {
            return slot.missionName
        }

        return "Slot \(slot.index + 1)"
    }

    private func flagBinding(_ flag: MissionFlagKind, slot: MissionSlot) -> Binding<Bool> {
        Binding(
            get: {
                switch flag {
                case .isActive: return slot.isActive
                case .travelObjComplete: return slot.travelObjComplete
                case .shipObjComplete: return slot.shipObjComplete
                case .missionFailed: return slot.missionFailed
                }
            },
            set: { newValue in
                perform {
                    try pilotFile.setMissionFlag(flag, to: newValue, missionIndex: slot.index)
                }
            }
        )
    }

    // Negative pay values are special codes (clear a legal record, take
    // cash), not negative credit amounts; see MissionPay. The amount itself
    // is already in the field, so plain credits just say "Credits".
    private func rewardDescription(_ pay: Int32) -> String {
        let decoded: MissionPay = MissionPay(pay)

        if case .credits = decoded {
            return "Credits"
        }

        return decoded.description(governmentName: governmentName)
    }

    private func governmentName(_ governmentID: Int) -> String {
        if let name = gameData.snapshot?.names.name(type: ResourceNameIndex.governments, id: governmentID) {
            return GameName(name).full
        }

        return "government \(governmentID)"
    }

    private func report(_ message: String) {
        errorMessage = message
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
