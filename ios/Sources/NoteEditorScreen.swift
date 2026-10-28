import SwiftUI

/// Plain Markdown editing of one note. Changes are saved a moment after typing stops and when leaving.
/// With no `noteID` it writes a new note, which is only created once something is typed.
struct NoteEditorScreen: View {
    @ObservedObject private var storage = NoteStorageManager.shared
    @Environment(\.dismiss) private var dismiss
    let noteID: Note.ID?

    @State private var title = ""
    @State private var content = ""
    @State private var loaded = false
    /// The title and text last loaded from or saved to the note. While the fields still match them,
    /// nothing was typed since, so nothing is saved and a newer version from another device shows
    @State private var syncedTitle = ""
    @State private var syncedContent = ""
    /// The note made from what was typed, when this screen started without one
    @State private var createdID: Note.ID?
    @State private var confirmingDelete = false
    @FocusState private var editorFocused: Bool

    private var note: Note? { (noteID ?? createdID).flatMap { id in storage.notes.first { $0.id == id } } }
    private var isNew: Bool { noteID == nil && createdID == nil }
    private var isEdited: Bool { title != syncedTitle || content != syncedContent }

    var body: some View {
        // One editor for a new note and an existing one, so the keyboard stays up when typing
        // creates the note
        if isNew || note != nil {
            fields
                .navigationTitle(note.map { $0.targetName ?? $0.categoryType.displayName } ?? "New Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let note {
                        Menu {
                            Button {
                                var pinned = note
                                pinned.isPinned.toggle()
                                storage.save(note: pinned)
                            } label: {
                                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                            }
                            Button(role: .destructive) { confirmingDelete = true } label: {
                                Label("Delete Note", systemImage: "trash")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
                .confirmationDialog("Delete this note?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        if let note { storage.delete(note: note) }
                        dismiss()
                    }
                }
                .onAppear {
                    guard !loaded else { return }
                    if let note { load(note) }
                    loaded = true
                    if content.isEmpty { editorFocused = true }
                }
                .onChange(of: [note?.title, note?.content]) { _, _ in
                    // A version saved on another device shows unless something was typed here
                    if let note, !isEdited { load(note) }
                }
                .task(id: [title, content]) {
                    try? await Task.sleep(for: .milliseconds(800))
                    guard !Task.isCancelled else { return }
                    save(leaving: false)
                }
                .onDisappear { save(leaving: true) }
        } else {
            ContentUnavailableView("Note not found", systemImage: "questionmark.folder",
                                   description: Text("It may have been deleted on another device."))
        }
    }

    private var fields: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title)
                .font(.title2.weight(.semibold))
                .padding(.horizontal)
                .padding(.top, 8)
            TextEditor(text: $content)
                .font(.body.monospaced())
                .padding(.horizontal, 12)
                .focused($editorFocused)
        }
    }

    private func load(_ note: Note) {
        title = note.title
        content = note.content
        syncedTitle = note.title
        syncedContent = note.content
    }

    /// Saves what was typed. Nothing is written when nothing was typed, so leaving a note never
    /// puts back an older version over one saved on another device. A note emptied here is
    /// removed when leaving it rather than kept as a blank file.
    private func save(leaving: Bool) {
        guard loaded else { return }
        let isBlank = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isNew {
            guard !isBlank else { return }
            createdID = storage.createNote(title: title, content: content, tags: Note.tags(in: content)).id
            syncedTitle = title
            syncedContent = content
            return
        }
        guard var updated = note else { return }
        if isBlank {
            if leaving { storage.delete(note: updated) }
            return
        }
        guard isEdited else { return }
        updated.title = title
        updated.content = content
        updated.tags = Note.tags(in: content)
        storage.save(note: updated)
        syncedTitle = title
        syncedContent = content
    }
}
