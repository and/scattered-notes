import Foundation

/// Browsing notes by where they live or what they mention: the Inbox, a project, a person (`@name`)
/// or a tag (`#name`). The phone's Browse screen uses it; the sidebar on the Mac follows the same rules.
public enum NoteBrowse {
    public enum Place: Hashable, Sendable {
        case all
        case inbox
        case project(String)
        case person(String)
        case tag(String)

        public var title: String {
            switch self {
            case .all: "All Notes"
            case .inbox: "Inbox"
            case .project(let name): name
            case .person(let name): "@" + name
            case .tag(let name): "#" + name
            }
        }

        /// Whether `note` is listed under this place. Names match without regard to case.
        public func contains(_ note: Note) -> Bool {
            switch self {
            case .all: true
            case .inbox: note.categoryType == .inbox
            case .project(let name): note.categoryType == .project && note.targetName == name
            case .person(let name): note.people.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            case .tag(let name): note.tags.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }
        }

        /// Where a note started here is filed: the Inbox or the project; people and tags are not folders,
        /// so a note started under one lands in the Inbox and begins with the mark that lists it there.
        public var destination: (category: CategoryType, targetName: String?) {
            if case .project(let name) = self { return (.project, name) }
            return (.inbox, nil)
        }

        /// The text a note started here begins with, so it shows up under this person or tag
        public var starterText: String? {
            switch self {
            case .person(let name): "@" + name + " "
            case .tag(let name): "#" + name + " "
            default: nil
            }
        }
    }

    public static func notes(in place: Place, of notes: [Note]) -> [Note] {
        place == .all ? notes : notes.filter(place.contains)
    }

    /// How many notes are in a project
    public static func count(project name: String, in notes: [Note]) -> Int {
        notes.filter { $0.categoryType == .project && $0.targetName == name }.count
    }

    /// Each name used across the notes with how many notes use it, the most used first and then by name.
    /// Names that differ only in case count as one, spelled as first seen.
    public static func counted(in notes: [Note], names: (Note) -> [String]) -> [(name: String, count: Int)] {
        var spelling: [String: String] = [:]
        var counts: [String: Int] = [:]
        for note in notes {
            let found = names(note)
            for name in Set(found.map { $0.lowercased() }) { counts[name, default: 0] += 1 }
            for name in found where spelling[name.lowercased()] == nil { spelling[name.lowercased()] = name }
        }
        return counts.map { (name: spelling[$0.key] ?? $0.key, count: $0.value) }
            .sorted {
                $0.count != $1.count
                    ? $0.count > $1.count
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}
