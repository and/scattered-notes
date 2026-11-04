import SwiftUI

extension Notification.Name {
    /// Asks the main window to open the note whose id is in `userInfo["id"]`
    static let openNote = Notification.Name("ScatteredNotes.openNote")
}

/// Right-margin column of the editor: the notes this note mentions, and the notes that mention it.
/// Reads the saved text, so a new mention shows up a moment after typing stops.
struct NoteLinksPanel: View {
    let noteID: UUID
    let index: NoteLinkIndex
    let notes: [UUID: Note]

    private var linkedNotes: [UUID] { index.linkedNotes(from: noteID) }
    private var backlinks: [UUID] { index.backlinks(to: noteID) }
    /// `[[Title]]` links that no note answers to
    private var unresolved: [NoteLink] {
        var seen = Set<String>()
        return index.links(from: noteID).filter { $0.target == nil && seen.insert($0.text.lowercased()).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Links")
                    .font(.headline)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)

                section("Links to", ids: linkedNotes, empty: "This note does not mention another note's title. Write a title, or [[Title]], to link.")
                if !unresolved.isEmpty {
                    Text("No note with this title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.wcagSecondaryText)
                        .padding(.horizontal, 4)
                        .padding(.top, 10)
                    ForEach(unresolved, id: \.text) { link in
                        Text("[[\(link.text)]]")
                            .font(.callout)
                            .foregroundColor(.wcagOrange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                    }
                }
                section("Linked from", ids: backlinks, empty: "No other note mentions this one.")
                    .padding(.top, 10)
            }
            .padding(12)
        }
        .frame(width: 240)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .accessibilityIdentifier("linksPanel")
    }

    @ViewBuilder
    private func section(_ title: String, ids: [UUID], empty: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.wcagSecondaryText)
            .padding(.horizontal, 4)
        if ids.isEmpty {
            Text(empty)
                .font(.caption)
                .foregroundColor(.wcagSecondaryText)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
        ForEach(ids, id: \.self) { id in
            if let note = notes[id] {
                LinkRow(note: note)
            }
        }
    }
}

private struct LinkRow: View {
    let note: Note
    @State private var isHovering = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openNote, object: nil, userInfo: ["id": note.id])
        } label: {
            HStack(spacing: 6) {
                Image(systemName: note.categoryType.iconName)
                    .foregroundColor(.wcagSecondaryText)
                Text(note.displayTitle)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.5) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Open \(note.displayTitle)")
    }
}
