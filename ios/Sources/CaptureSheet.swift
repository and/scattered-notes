import SwiftUI

/// Write a thought down fast and file it in the Inbox, a project or an area.
struct CaptureSheet: View {
    @ObservedObject private var storage = NoteStorageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var destination = Destination.inbox
    @FocusState private var focused: Bool

    enum Destination: Hashable {
        case inbox
        case project(String)
        case area(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .focused($focused)
                } footer: {
                    Text("Lines like \"call the bank tomorrow\" or \"- [ ] renew passport\" show up on the Dashboard.")
                }
                Section {
                    Picker("Save to", selection: $destination) {
                        Label("Inbox", systemImage: CategoryType.inbox.iconName).tag(Destination.inbox)
                        ForEach(storage.projects) { project in
                            Label(project.name, systemImage: CategoryType.project.iconName).tag(Destination.project(project.name))
                        }
                        ForEach(storage.areas) { area in
                            Label(area.name, systemImage: CategoryType.area.iconName).tag(Destination.area(area.name))
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
        // Words starting with # become tags, as in the Mac Quick Capture
        let tags = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.hasPrefix("#") && $0.count > 1 }
            .map { String($0.dropFirst()).trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty }
        switch destination {
        case .inbox:
            storage.createNote(content: trimmed, tags: tags)
        case .project(let name):
            storage.createNote(content: trimmed, category: .project, targetName: name, tags: tags)
        case .area(let name):
            storage.createNote(content: trimmed, category: .area, targetName: name, tags: tags)
        }
        dismiss()
    }
}
