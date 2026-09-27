import SwiftUI

// What the mission says to the player, one collapsible part per moment
// (offered, accepted, completed...). Text switches on story flags and
// gender are applied for this pilot; placeholders such as <DST> are left as
// written, since the game only fills them in once the mission is running.
struct MissionTextView: View {
    let mission: MissionDefinition
    let descriptions: [Int: String]
    @ObservedObject var pilotFile: PilotFile

    // The offer text opens by default; the rest stay folded.
    @State private var expandedIDs: Set<Int>?

    var body: some View {
        let parts: [MissionTextPart] = MissionText.parts(for: mission, descriptions: descriptions)

        VStack(alignment: .leading, spacing: 6) {
            // Styled like the diagnosis view's section titles below it.
            Text("Mission text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if parts.isEmpty {
                Text("This mission has no text in the loaded game data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(parts) { part in
                    DisclosureGroup(isExpanded: expansionBinding(part, defaultID: parts[0].id)) {
                        Text(resolved(part.text))
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } label: {
                        Text(part.title)
                            .font(.callout.weight(.medium))
                    }
                }
            }
        }
    }

    private func resolved(_ text: String) -> String {
        MissionText.resolveSwitches(
            in: text,
            storyFlags: MissionBits.decodeAll(from: pilotFile.workingBytes),
            isMale: pilotFile.isMale
        )
    }

    private func expansionBinding(_ part: MissionTextPart, defaultID: Int) -> Binding<Bool> {
        Binding(
            get: { (expandedIDs ?? [defaultID]).contains(part.id) },
            set: { isExpanded in
                var ids: Set<Int> = expandedIDs ?? [defaultID]

                if isExpanded {
                    ids.insert(part.id)
                } else {
                    ids.remove(part.id)
                }

                expandedIDs = ids
            }
        )
    }
}
