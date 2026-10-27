import SwiftUI

public struct MainSplitView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    
    @State private var sidebarSelection: SidebarSelection = .dashboard
    @State private var selectedNote: Note? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    public init() {}
    
    public var body: some View {
        splitView
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
        .onChange(of: selectedNote?.id) { _, newID in
            // The dashboard hides the editor, so picking or creating a note must leave it
            if newID != nil, sidebarSelection == .dashboard {
                sidebarSelection = .all
            }
        }
        .onAppear {
            if selectedNote == nil, sidebarSelection != .dashboard, let first = storageManager.notes.first {
                selectedNote = first
            }
        }
    }
    
    /// The dashboard has no note list, so it uses a two-column layout
    @ViewBuilder
    private var splitView: some View {
        if sidebarSelection == .dashboard {
            NavigationSplitView {
                sidebar
            } detail: {
                detailView
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } content: {
                NoteListView(selectedCategory: sidebarSelection, selectedNote: $selectedNote)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
            } detail: {
                detailView
            }
        }
    }

    private var sidebar: some View {
        SidebarView(selection: $sidebarSelection)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }

    @ViewBuilder
    private var detailView: some View {
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
