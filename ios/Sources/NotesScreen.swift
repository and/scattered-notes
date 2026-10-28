import SwiftUI

/// Every note, newest first, with search over titles, text and tags.
struct NotesScreen: View {
    @ObservedObject private var storage = NoteStorageManager.shared
    @State private var query = ""
    @State private var path: [Note.ID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if query.isEmpty {
                    ForEach(storage.notes) { note in
                        NavigationLink(value: note.id) { NoteRow(note: note, snippet: nil) }
                    }
                    .onDelete { offsets in
                        offsets.map { storage.notes[$0] }.forEach(storage.delete(note:))
                    }
                } else {
                    ForEach(NoteSearch.search(query, in: storage.notes)) { result in
                        NavigationLink(value: result.note.id) { NoteRow(note: result.note, snippet: result.snippet) }
                    }
                }
            }
            .overlay {
                if storage.notes.isEmpty {
                    ContentUnavailableView("No notes yet", systemImage: "note.text",
                                           description: Text("Tap the pencil to write one."))
                }
            }
            .navigationTitle("Notes")
            .navigationDestination(for: Note.ID.self) { NoteEditorScreen(noteID: $0) }
            .searchable(text: $query, prompt: "Search all notes")
            .refreshable { NotesFolder.refresh() }
            .toolbar {
                Button {
                    path.append(storage.createNote().id)
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let snippet: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
                }
                Text(note.displayTitle).font(.headline).lineLimit(1)
            }
            let preview = snippet ?? note.previewExcerpt
            if !preview.isEmpty {
                Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
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
}
