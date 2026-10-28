import SwiftUI

/// Write a thought down fast and file it in the Inbox or a project.
struct CaptureSheet: View {
    @ObservedObject private var storage = NoteStorageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var destination = Destination.inbox
    @FocusState private var focused: Bool

    enum Destination: Hashable {
        case inbox
        case project(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .focused($focused)
                } footer: {
                    Text("Lines like \"call the bank tomorrow\" or \"- [ ] renew passport\" show up on the Dashboard. #tag tags the note and @name mentions a person.")
                }
                Section {
                    Picker("Save to", selection: $destination) {
                        Label("Inbox", systemImage: CategoryType.inbox.iconName).tag(Destination.inbox)
                        ForEach(storage.projects) { project in
                            Label(project.name, systemImage: CategoryType.project.iconName).tag(Destination.project(project.name))
                        }
                    }
                }
            }
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tags = Note.tags(in: trimmed)
        switch destination {
        case .inbox:
            storage.createNote(content: trimmed, tags: tags)
        case .project(let name):
            storage.createNote(content: trimmed, category: .project, targetName: name, tags: tags)
        }
        dismiss()
    }
}
