import SwiftUI

/// Every note, newest first, with search over titles, text and tags.
struct NotesScreen: View {
    @ObservedObject private var storage = NoteStorageManager.shared
    @State private var query = ""
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if query.isEmpty {
                    ForEach(storage.notes) { note in
                        NavigationLink(value: note.id) { NoteRow(note: note, snippet: nil, terms: []) }
                    }
                    .onDelete { offsets in
                        offsets.map { storage.notes[$0] }.forEach(storage.delete(note:))
                    }
                } else {
                    let terms = NoteSearch.terms(in: query)
                    ForEach(NoteSearch.search(query, in: storage.notes)) { result in
                        NavigationLink(value: result.note.id) { NoteRow(note: result.note, snippet: result.snippet, terms: terms) }
                    }
                }
            }
            .overlay {
                if storage.notes.isEmpty {
                    ContentUnavailableView("No notes yet", systemImage: "note.text",
                                           description: Text("Tap the pencil to write one."))
                } else if !query.isEmpty && NoteSearch.search(query, in: storage.notes, limit: 1).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Notes")
            .navigationDestination(for: Note.ID.self) { NoteEditorScreen(noteID: $0) }
            .navigationDestination(for: NewNote.self) { _ in NoteEditorScreen(noteID: nil) }
            .searchable(text: $query, prompt: "Search all notes")
            .refreshable { NotesFolder.refresh() }
            .toolbar {
                Button {
                    path.append(NewNote())
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
            }
        }
    }
}

/// Opens the editor on a note that doesn't exist until something is typed
private struct NewNote: Hashable {}

private struct NoteRow: View {
    let note: Note
    let snippet: String?
    /// Search terms to highlight; empty when not searching
    let terms: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
                }
                Text(highlighted(note.displayTitle)).font(.headline).lineLimit(1)
            }
            let preview = snippet ?? note.previewExcerpt
            if !preview.isEmpty {
                Text(highlighted(preview)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 4) {
                Image(systemName: note.categoryType.iconName)
                Text(note.targetName ?? note.categoryType.displayName)
                Text("·")
                Text(note.updatedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Bolds every match of the search terms, ignoring case and accents like the search itself.
    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        for term in terms {
            let needle = term.hasPrefix("#") ? String(term.dropFirst()) : term
            guard !needle.isEmpty else { continue }
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                if let range = Range(found, in: result) {
                    result[range].inlinePresentationIntent = .stronglyEmphasized
                    result[range].foregroundColor = .primary
                }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return result
    }
}
