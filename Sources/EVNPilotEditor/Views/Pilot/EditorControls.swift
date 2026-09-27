import SwiftUI

// Shared editing controls for the pilot workspace. Every control commits
// through a throwing closure so PilotFile's byte-level setters stay the only
// path that writes to a save file.

enum WorkspaceError: LocalizedError {
    case missingField(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .missingField(let id):
            return "The field \"\(id)\" is missing from FieldSchema.json."

        case .invalidValue(let message):
            return message
        }
    }
}

extension View {
    // One consistent alert for any failed edit, so no pane has to repeat
    // the Binding boilerplate.
    func editErrorAlert(_ message: Binding<String?>) -> some View {
        alert("Could Not Apply Change", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { isPresented in
                if !isPresented {
                    message.wrappedValue = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

// Game resource names often carry a designer note after a semicolon
// (e.g. "Shuttle;Second-Hand - poor"). The game only shows the part before
// it, but the note is what tells otherwise identical entries apart.
struct GameName {
    let title: String
    let note: String?

    init(_ raw: String) {
        let parts: [Substring] = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        let title: String = parts.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? raw

        self.title = title.isEmpty ? raw : title

        if parts.count > 1 {
            let note: String = String(parts[1]).trimmingCharacters(in: .whitespaces)
            self.note = note.isEmpty ? nil : note
        } else {
            self.note = nil
        }
    }

    var full: String {
        guard let note else { return title }
        return "\(title) (\(note))"
    }
}

// Whole-number field that saves on Return or when focus leaves the field,
// and rejects out-of-range input instead of writing it.
//
// Until clicked, it draws the number in a field-shaped box instead of a real
// text field. Pages like Ranks & Events show dozens of these, and creating
// a real AppKit text field for each one made opening the page take most of
// a second. The real field is swapped in only while editing.
struct IntegerField: View {
    let value: Int
    let range: ClosedRange<Int>
    let commit: (Int) throws -> Void
    let onError: (String) -> Void
    var width: CGFloat = 110

    @State private var text: String = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            editingField
        } else {
            Button {
                text = String(value)
                isEditing = true
            } label: {
                Text(String(value))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(nsColor: .separatorColor))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: width)
            .help("Click to edit")
        }
    }

    private var editingField: some View {
        TextField("", text: $text)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .focused($isFocused)
            .onAppear {
                // Deferred one tick: macOS can drop a focus request made
                // while the field is still being laid out.
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    finishEditing()
                }
            }
            .onSubmit {
                finishEditing()
            }
            .onExitCommand {
                // Escape cancels without saving.
                text = String(value)
                isEditing = false
            }
    }

    private func finishEditing() {
        guard isEditing else { return }

        apply()
        isEditing = false
    }

    private func apply() {
        let trimmed: String = text.trimmingCharacters(in: .whitespaces)

        guard let parsed = Int(trimmed), range.contains(parsed) else {
            onError("\"\(text)\" is not a whole number from \(range.lowerBound) to \(range.upperBound).")
            text = String(value)
            return
        }

        guard parsed != value else { return }

        do {
            try commit(parsed)
        } catch {
            onError(error.localizedDescription)
            text = String(value)
        }
    }
}

// Single-line text field with the same save-on-Return/focus-loss behavior.
struct TextCommitField: View {
    let value: String
    let placeholder: String
    let commit: (String) throws -> Void
    let onError: (String) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onAppear {
                text = value
            }
            .onChange(of: value) { _, newValue in
                if !isFocused {
                    text = newValue
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    apply()
                }
            }
            .onSubmit {
                apply()
            }
    }

    private func apply() {
        guard text != value else { return }

        do {
            try commit(text)
        } catch {
            onError(error.localizedDescription)
            text = value
        }
    }
}

// Pushes and pops cursors for one view, counting what it pushed. A view can
// disappear mid-hover or mid-drag without getting its "exit" or "end"
// callback, which left its cursor stuck on AppKit's shared stack; calling
// popAll() from onDisappear takes back exactly what this view added.
final class CursorStack {
    private var pushedCount: Int = 0

    func push(_ cursor: NSCursor) {
        cursor.push()
        pushedCount += 1
    }

    func pop() {
        guard pushedCount > 0 else { return }

        NSCursor.pop()
        pushedCount -= 1
    }

    func popAll() {
        while pushedCount > 0 {
            pop()
        }
    }
}

// Marks fields whose place in the pilot file is inferred from the format
// notes and sample pilots but hasn't been confirmed by changing it and
// checking the result in the game (the "probable" fields in project.md).
struct UnconfirmedFieldNote: View {
    let fields: String

    var body: some View {
        Label("\(fields): where this is stored in the pilot file is inferred, not yet confirmed in the game. Keep the backup until you've checked the result.", systemImage: "questionmark.circle")
    }
}

// Searchable chooser used for ships, outfits, weapons, and places.
struct PickerItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let detail: String
}

struct CatalogPickerSheet: View {
    let title: String
    let items: [PickerItem]
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    // A plain search field instead of NavigationStack + .searchable: in a
    // macOS sheet, the toolbar search field and the List fight over first
    // responder forever, pinning the CPU and freezing the app.
    var body: some View {
        let visibleItems: [PickerItem] = filteredItems

        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top])

            TextField("Search by name or ID", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding()

            Divider()

            List(visibleItems) { item in
                Button {
                    onPick(item.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)

                        if !item.detail.isEmpty {
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if visibleItems.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 520)
        .onAppear {
            searchFocused = true
        }
    }

    private var filteredItems: [PickerItem] {
        let query: String = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }

        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || item.detail.localizedCaseInsensitiveContains(query)
                || String(item.id) == query
        }
    }
}

// Search box plus a "hide untouched entries" switch, shared by the panes
// that list hundreds of systems, planets, or characters.
struct ListFilterBar: View {
    @Binding var searchText: String
    @Binding var onlyChanged: Bool
    let onlyChangedLabel: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Filter by name or ID", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Toggle(onlyChangedLabel, isOn: $onlyChanged)
                .toggleStyle(.checkbox)
                .fixedSize()
        }
    }
}

// Colored label for a mission's state in the current pilot's story.
struct MissionStatusBadge: View {
    let status: MissionStatus

    var body: some View {
        Label(status.displayName, systemImage: status.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize()
    }
}

extension MissionStatus {
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .available: return "Available"
        case .completed: return "Done"
        case .blocked: return "Blocked"
        case .impossible: return "Can't Happen"
        }
    }

    var symbolName: String {
        switch self {
        case .active: return "play.circle.fill"
        case .available: return "circle.dashed"
        case .completed: return "checkmark.circle.fill"
        case .blocked: return "exclamationmark.triangle.fill"
        case .impossible: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .active: return .blue
        case .available: return .green
        case .completed: return .secondary
        case .blocked: return .orange
        case .impossible: return .red
        }
    }
}

extension IssueSeverity {
    var symbolName: String {
        switch self {
        case .blocker: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .blocker: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }
}
