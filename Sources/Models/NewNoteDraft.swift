import SwiftUI

/// Where a note made from the current view starts: the project it is made under, or the
/// person or tag it is marked with so it is listed there. One rule for every way of
/// making a note (the ✎ button, ⌘N), so they can't drift apart.
struct NewNoteDraft: Equatable {
    var category: CategoryType = .inbox
    var targetName: String?
    var content: String = ""

    init(for selection: SidebarSelection) {
        switch selection {
        case .all, .inbox, .dashboard:
            break
        case .project(let name):
            category = .project
            targetName = name
        case .person(let name):
            content = "@\(name) "
        case .tag(let name):
            content = "#\(name) "
        }
    }
}

/// The New Note command (⌘N), supplied by whichever note list has the window's focus.
/// Nil when none does (Settings in front), which disables the menu item.
private struct NewNoteActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newNoteAction: (() -> Void)? {
        get { self[NewNoteActionKey.self] }
        set { self[NewNoteActionKey.self] = newValue }
    }
}
