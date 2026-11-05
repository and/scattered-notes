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
    let related: RelatedIndex
    let notes: [UUID: Note]
    /// Notes close in meaning, or nil when suggestions are turned off
    let suggested: SuggestedIndex?
    /// Writes `[[Title]]` over a mention of that note
    let onMakeLink: (UUID) -> Void

    private var linkedNotes: [UUID] { index.linkedNotes(from: noteID) }
    private var backlinks: [UUID] { index.backlinks(to: noteID) }
    /// `[[Title]]` links that no note answers to
    private var unresolved: [NoteLink] {
        var seen = Set<String>()
        return index.links(from: noteID).filter { $0.target == nil && seen.insert($0.text.lowercased()).inserted }
    }

    /// Notes mentioned only in plain text, never as `[[Title]]`: the ones that can be made a link
    private var canMakeLink: Set<UUID> {
        let links = index.links(from: noteID)
        let explicit = Set(links.filter(\.isExplicit).compactMap(\.target))
        let plain = Set(links.filter { !$0.isExplicit }.compactMap(\.target))
        return plain.subtracting(explicit).filter { id in
            notes[id].flatMap { NoteLinkIndex.explicitText(forTitle: $0.displayTitle) } != nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Links")
                    .font(.headline)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)

                section("Links to", ids: linkedNotes, empty: "This note does not mention another note's title. Write a title, or [[Title]], to link.",
                        makeLink: canMakeLink)
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

                // Notes already listed above are not repeated here
                let similar = related.related(to: noteID, excluding: Set(linkedNotes + backlinks))
                let listed = Set(linkedNotes + backlinks + similar.map(\.id))
                if !similar.isEmpty {
                    Text("Related")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.wcagSecondaryText)
                        .padding(.horizontal, 4)
                        .padding(.top, 10)
                    ForEach(similar, id: \.id) { item in
                        if let note = notes[item.id] {
                            LinkRow(note: note, why: why(item))
                        }
                    }
                }

                if let suggested {
                    let ideas = suggested.suggestions(for: noteID, excluding: listed)
                    if !ideas.isEmpty {
                        Text("Suggested")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.wcagSecondaryText)
                            .padding(.horizontal, 4)
                            .padding(.top, 10)
                        ForEach(ideas, id: \.id) { idea in
                            if let note = notes[idea.id] {
                                LinkRow(note: note, why: "Similar meaning")
                            }
                        }
                        Text("By meaning, worked out on this Mac. Only a guess.")
                            .font(.caption2)
                            .foregroundColor(.wcagSecondaryText)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 240)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .accessibilityIdentifier("linksPanel")
    }

    /// Why a note is listed: the tags and people it shares, else the words
    private func why(_ item: RelatedNote) -> String {
        if !item.sharedMarks.isEmpty { return "Shares " + item.sharedMarks.joined(separator: ", ") }
        return "Also about " + item.sharedWords.joined(separator: ", ")
    }

    @ViewBuilder
    private func section(_ title: String, ids: [UUID], empty: String, makeLink: Set<UUID> = []) -> some View {
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
                LinkRow(note: note, onMakeLink: makeLink.contains(id) ? { onMakeLink(id) } : nil)
            }
        }
    }
}

private struct LinkRow: View {
    let note: Note
    var why: String?
    /// Set when the mention can be made an explicit link: shows a button for it
    var onMakeLink: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 2) {
            openButton
            if let onMakeLink {
                Button(action: onMakeLink) {
                    Image(systemName: "link.badge.plus")
                        .foregroundColor(.wcagBlue)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Make this a link: writes [[\(note.displayTitle)]] in the note where it is mentioned")
                .accessibilityLabel("Make this a link")
                .accessibilityIdentifier("makeLink")
            }
        }
    }

    private var openButton: some View {
        Button {
            NotificationCenter.default.post(name: .openNote, object: nil, userInfo: ["id": note.id])
        } label: {
            HStack(spacing: 6) {
                Image(systemName: note.categoryType.iconName)
                    .foregroundColor(.wcagSecondaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.displayTitle)
                        .lineLimit(1)
                    if let why {
                        Text(why)
                            .font(.caption)
                            .foregroundColor(.wcagSecondaryText)
                            .lineLimit(1)
                    }
                }
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

/// The bar between the Agenda and Links panels: a line with room around it to grab, and the up-and-down arrows
/// as the pointer comes over it. Double-click puts the panels back to their usual sizes.
struct PaneResizeHandle: View {
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.clear
            Divider()
            if isHovering {
                Capsule()
                    .fill(Color.wcagSecondaryText.opacity(0.6))
                    .frame(width: 32, height: 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            isHovering = inside
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .help("Drag to change the height of Links. Double-click to reset.")
        .accessibilityLabel("Resize Links")
        .accessibilityIdentifier("linksResizeHandle")
    }
}
