import SwiftUI

/// Plain Markdown editing of one note. Changes are saved a moment after typing stops and when leaving.
struct NoteEditorScreen: View {
    @ObservedObject private var storage = NoteStorageManager.shared
    @Environment(\.dismiss) private var dismiss
    let noteID: Note.ID

    @State private var title = ""
    @State private var content = ""
    @State private var loaded = false
    @State private var confirmingDelete = false
    @FocusState private var editorFocused: Bool

    private var note: Note? { storage.notes.first { $0.id == noteID } }

    var body: some View {
        Group {
            if let note {
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
                .navigationTitle(note.targetName ?? note.categoryType.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
                .confirmationDialog("Delete this note?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        storage.delete(note: note)
                        dismiss()
                    }
                }
                .onAppear {
                    guard !loaded else { return }
                    title = note.title
                    content = note.content
                    loaded = true
                    if note.content.isEmpty { editorFocused = true }
                }
                .task(id: [title, content]) {
                    try? await Task.sleep(for: .milliseconds(800))
                    guard !Task.isCancelled else { return }
                    save()
                }
                .onDisappear(perform: save)
            } else {
                ContentUnavailableView("Note not found", systemImage: "questionmark.folder",
                                       description: Text("It may have been deleted on another device."))
            }
        }
    }

    private func save() {
        guard loaded, var updated = note else { return }
        // A note created here and left empty is dropped rather than kept as a blank file
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            storage.delete(note: updated)
            return
        }
        updated.title = title
        updated.content = content
        storage.save(note: updated)
    }
}
