import SwiftUI

/// Dragging a note from the list onto a project, or onto the Inbox, in the sidebar. The note travels as
/// its ID in a short text, so a drop looks the note up again and never carries a stale copy.
enum NoteDrag {
    private static let prefix = "scatterednotes-note:"

    static func payload(for note: Note) -> String { prefix + note.id.uuidString }

    static func noteID(from payload: String) -> UUID? {
        payload.hasPrefix(prefix) ? UUID(uuidString: String(payload.dropFirst(prefix.count))) : nil
    }

    /// Where a note dropped on this sidebar row ends up; nil for rows that take no drops.
    static func destination(for selection: SidebarSelection) -> (category: CategoryType, targetName: String?)? {
        switch selection {
        case .inbox: (.inbox, nil)
        case .project(let name): (.project, name)
        default: nil
        }
    }
}

/// Makes a sidebar row accept dragged notes and outline itself while one is over it.
struct NoteDropTarget: ViewModifier {
    let selection: SidebarSelection
    @Binding var highlighted: SidebarSelection?
    let onDrop: (UUID, SidebarSelection) -> Bool
    /// How far a sidebar row reaches past its label to its edges: the space the list leaves around it
    private static let reachX: CGFloat = 9
    private static let reachY: CGFloat = 4

    func body(content: Content) -> some View {
        content
            // The row's content is only as tall as its text, so the drop area is widened to the whole row:
            // padded out to the row's edges here, then pulled back so the layout stays as it was
            .padding(.vertical, Self.reachY)
            .padding(.horizontal, Self.reachX)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { payloads, _ in
                guard let id = payloads.lazy.compactMap(NoteDrag.noteID).first else { return false }
                return onDrop(id, selection)
            } isTargeted: { targeted in
                if targeted {
                    highlighted = selection
                } else if highlighted == selection {
                    highlighted = nil
                }
            }
            // The outline is drawn on the padded row, so it frames the whole row and not only the label
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.wcagBlue, lineWidth: 2)
                    .opacity(highlighted == selection ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .padding(.vertical, -Self.reachY)
            .padding(.horizontal, -Self.reachX)
    }
}
