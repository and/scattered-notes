import Foundation

/// A place the quick switcher can jump to: the Dashboard, All Notes, the Inbox, a project, a person or a tag.
struct GoToTarget: Identifiable, Hashable {
    let selection: SidebarSelection
    let title: String
    /// Notes listed there; nil for the Dashboard
    let count: Int?
    let icon: String

    var id: SidebarSelection { selection }
}

/// What the quick switcher offers and how typing narrows it, kept apart from the view so it can be tested.
enum GoToTargets {
    /// Every place in the sidebar's order: Quick Access, projects, people, then tags. People and tags
    /// are the names used across the notes, differing only in case counting once, as in the sidebar.
    static func all(projects: [ProjectArea], notes: [Note]) -> [GoToTarget] {
        var targets = [
            GoToTarget(selection: .dashboard, title: "Dashboard", count: nil, icon: "square.grid.2x2.fill"),
            GoToTarget(selection: .all, title: "All Notes", count: notes.count, icon: "tray.2.fill"),
            GoToTarget(selection: .inbox, title: "Inbox", count: notes.filter { $0.categoryType == .inbox }.count, icon: "tray.fill"),
        ]
        for project in projects {
            let count = notes.filter { $0.categoryType == .project && $0.targetName == project.name }.count
            targets.append(GoToTarget(selection: .project(name: project.name), title: project.name, count: count, icon: project.iconName))
        }
        targets += named(notes.map(\.people), icon: "person.fill") { .person(name: $0) }
        targets += named(notes.map(\.tags), icon: "number") { .tag(name: $0) }
        return targets
    }

    private static func named(_ lists: [[String]], icon: String, selection: (String) -> SidebarSelection) -> [GoToTarget] {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for names in lists {
            for key in Set(names.map { $0.lowercased() }) { counts[key, default: 0] += 1 }
            for name in names where spelling[name.lowercased()] == nil { spelling[name.lowercased()] = name }
        }
        return counts
            .map { (name: spelling[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { GoToTarget(selection: selection($0.name), title: $0.name, count: $0.count, icon: icon) }
    }

    /// The targets matching what was typed, best first. Case and accents are ignored. A name that starts
    /// with the text comes before one with a word that does, and that before one that only contains it.
    /// A leading `#` looks only at tags and a leading `@` only at people.
    static func matching(_ query: String, in targets: [GoToTarget]) -> [GoToTarget] {
        var text = query.trimmingCharacters(in: .whitespaces)
        var candidates = targets
        if text.hasPrefix("#") {
            text.removeFirst()
            candidates = targets.filter { if case .tag = $0.selection { true } else { false } }
        } else if text.hasPrefix("@") {
            text.removeFirst()
            candidates = targets.filter { if case .person = $0.selection { true } else { false } }
        }
        let needle = fold(text)
        guard !needle.isEmpty else { return candidates }

        func rank(_ target: GoToTarget) -> Int? {
            let title = fold(target.title)
            if title.hasPrefix(needle) { return 0 }
            if title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(needle) }) { return 1 }
            return title.contains(needle) ? 2 : nil
        }
        return candidates.enumerated()
            .compactMap { index, target in rank(target).map { (rank: $0, index: index, target: target) } }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map(\.target)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
