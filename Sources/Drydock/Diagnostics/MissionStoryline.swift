import Foundation

// Storyline names for display. The scenario's mission names usually carry a
// tag after the ";" (e.g. "Vellos3", "Rebel II14"), which says which
// storyline a mission belongs to far better than its title does.
enum MissionStoryline {
    static func tag(of mission: MissionDefinition?) -> String? {
        guard let name = mission?.name, let separator = name.firstIndex(of: ";") else { return nil }
        return tag(ofNote: String(name[name.index(after: separator)...]))
    }

    // The storyline part of a note is everything before its first digit,
    // so "Rebel II14 - Unregistered cutoff" becomes "Rebel II".
    static func tag(ofNote note: String?) -> String? {
        guard let note else { return nil }

        let prefix: Substring = note.trimmingCharacters(in: .whitespaces).prefix { !$0.isNumber }
        let tag: String = prefix.trimmingCharacters(in: CharacterSet(charactersIn: " -.,"))

        guard tag.count >= 3, tag.first?.isLetter == true else { return nil }
        return tag
    }
}
