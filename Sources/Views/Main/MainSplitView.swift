import SwiftUI

public struct MainSplitView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    
    @State private var sidebarSelection: SidebarSelection = .all
    @State private var selectedNote: Note? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            NoteListView(selectedCategory: sidebarSelection, selectedNote: $selectedNote)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
        } detail: {
            if let note = selectedNote {
                NoteDetailEditorView(note: note)
                    .id(note.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Select a note to view or edit")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Press ⌥N anywhere to capture a quick note")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(windowTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    QuickCapturePanel.shared.showPanel()
                }) {
                    Label("Quick Capture (⌥N)", systemImage: "bolt.fill")
                }
                .help("Open Quick Capture (⌥N)")
            }
        }
        .onAppear {
            if selectedNote == nil, let first = storageManager.notes.first {
                selectedNote = first
            }
        }
    }
    
    private var windowTitle: String {
        if let note = selectedNote {
            return "\(note.displayTitle) — \(sidebarSelection.title)"
        }
        return sidebarSelection.title
    }
}
