import SwiftUI

public struct MainSplitView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    
    @State private var sidebarSelection: SidebarSelection = .dashboard
    @State private var selectedNote: Note? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            NoteListView(selectedCategory: sidebarSelection, selectedNote: $selectedNote)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
        } detail: {
            if sidebarSelection == .dashboard {
                DashboardView { note in
                    selectedNote = note
                    sidebarSelection = .all
                }
            } else if let note = selectedNote {
                NoteDetailEditorView(note: note)
                    .id(note.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 44))
                        .foregroundColor(.wcagSecondaryText.opacity(0.6))
                    Text("Select a note to view or edit")
                        .font(.title3)
                        .foregroundColor(.wcagSecondaryText)
                    Text("Press ⌥N anywhere to capture a quick note")
                        .font(.subheadline)
                        .foregroundColor(.wcagSecondaryText)
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
        .onChange(of: sidebarSelection) { _, newSelection in
            // The dashboard uses the full width; note lists bring back the middle column
            columnVisibility = newSelection == .dashboard ? .doubleColumn : .all
        }
        .onAppear {
            if selectedNote == nil, let first = storageManager.notes.first {
                selectedNote = first
            }
        }
    }
    
    private var windowTitle: String {
        if sidebarSelection == .dashboard {
            return sidebarSelection.title
        }
        if let note = selectedNote {
            return "\(note.displayTitle) — \(sidebarSelection.title)"
        }
        return sidebarSelection.title
    }
}
