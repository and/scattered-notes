import SwiftUI

/// The Notes tab, laid out like Apple's Notes app: a list of folders (here the Inbox, each project,
/// each person and each tag, with how many notes they hold), and a list of notes behind each one.
/// Typing in the search bar searches every note.
struct NotesScreen: View {
    @ObservedObject private var storage = NoteStorageManager.shared
    @State private var query = ""
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            let notes = storage.notes
            List {
                if query.isEmpty {
                    Section {
                        FolderRow(place: .all, icon: "tray.full", count: notes.count)
                        FolderRow(place: .inbox, icon: "tray", count: NoteBrowse.notes(in: .inbox, of: notes).count)
                    }
                    if !storage.projects.isEmpty {
                        Section("Projects") {
                            ForEach(storage.projects) { project in
                                FolderRow(place: .project(project.name), icon: project.iconName,
                                          count: NoteBrowse.count(project: project.name, in: notes))
                            }
                        }
                    }
                    let people = NoteBrowse.counted(in: notes) { storage.people(in: $0) }
                    if !people.isEmpty {
                        Section("People") {
                            ForEach(people, id: \.name) { FolderRow(place: .person($0.name), icon: "person", count: $0.count) }
                        }
                    }
                    let tags = NoteBrowse.counted(in: notes) { $0.tags }
                    if !tags.isEmpty {
                        Section("Tags") {
                            ForEach(tags, id: \.name) { FolderRow(place: .tag($0.name), icon: "number", count: $0.count) }
                        }
                    }
                } else {
                    let terms = NoteSearch.terms(in: query)
                    ForEach(NoteSearch.search(query, in: notes)) { result in
                        NavigationLink(value: result.note.id) { NoteRow(note: result.note, snippet: result.snippet, terms: terms) }
                    }
                }
            }
            .overlay {
                if !query.isEmpty && NoteSearch.search(query, in: notes, limit: 1).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Folders")
            .navigationDestination(for: NoteBrowse.Place.self) { PlaceNotesScreen(place: $0) }
            .navigationDestination(for: Note.ID.self) { NoteEditorScreen(noteID: $0) }
            .navigationDestination(for: NewNote.self) { NoteEditorScreen(noteID: nil, startsIn: $0.place) }
            // Always shown: by default iOS hides it until the list is pulled down
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search all notes")
            .refreshable { NotesFolder.refresh() }
            .toolbar {
                Button {
                    path.append(NewNote(place: .inbox))
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
            }
        }
    }
}

/// Opens the editor on a note that doesn't exist until something is typed, filed under `place`
private struct NewNote: Hashable {
    let place: NoteBrowse.Place
}

/// One folder in the list: its icon, name and note count, and the chevron the system adds
private struct FolderRow: View {
    let place: NoteBrowse.Place
    let icon: String
    let count: Int

    var body: some View {
        NavigationLink(value: place) {
            HStack {
                Label(place.title, systemImage: icon)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(place.title), \(count) notes")
    }
}

/// The notes of one folder, newest first, with search inside it
private struct PlaceNotesScreen: View {
    let place: NoteBrowse.Place
    @ObservedObject private var storage = NoteStorageManager.shared
    @State private var query = ""

    var body: some View {
        let notes = NoteBrowse.notes(in: place, of: storage.notes)
        List {
            if query.isEmpty {
                ForEach(notes) { note in
                    NavigationLink(value: note.id) { NoteRow(note: note, snippet: nil, terms: []) }
                }
                .onDelete { offsets in
                    offsets.map { notes[$0] }.forEach(storage.delete(note:))
                }
            } else {
                let terms = NoteSearch.terms(in: query)
                ForEach(NoteSearch.search(query, in: notes)) { result in
                    NavigationLink(value: result.note.id) { NoteRow(note: result.note, snippet: result.snippet, terms: terms) }
                }
            }
        }
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView("No notes yet", systemImage: "note.text",
                                       description: Text("Tap the pencil to write one."))
            } else if !query.isEmpty && NoteSearch.search(query, in: notes, limit: 1).isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle(place.title)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .refreshable { NotesFolder.refresh() }
        .toolbar {
            NavigationLink(value: NewNote(place: place)) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
    }
}

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
