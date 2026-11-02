import SwiftUI

public struct MainSplitView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    @ObservedObject var settings = AppSettings.shared
    
    @State private var sidebarSelection: SidebarSelection = .dashboard
    @State private var selectedNote: Note? = nil
    @State private var showingSearch = false
    @State private var showingGoTo = false
    @Environment(\.undoManager) private var undoManager
    @State private var focusRequest: MainPane?
    @State private var sidebarHasFocus = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    public init() {}
    
    public var body: some View {
        splitView
        .navigationTitle(windowTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingSearch = true }) {
                    Label("Search All Notes (⌘K, \(settings.searchShortcut.displayString) anywhere)", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("k", modifiers: .command)
                .help("Search all notes (⌘K, or \(settings.searchShortcut.displayString) from any app)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    QuickCapturePanel.shared.showPanel()
                }) {
                    Label("Quick Capture (\(settings.quickCaptureShortcut.displayString))", systemImage: "bolt.fill")
                }
                .help("Open Quick Capture (\(settings.quickCaptureShortcut.displayString))")
            }
        }
        .sheet(isPresented: $showingSearch) {
            SearchPaletteView(
                onOpen: { note, terms in
                    showingSearch = false
                    selectedNote = note
                    sidebarSelection = .all
                    EditorFocus.request(noteID: note.id, terms: terms)
                },
                onClose: { showingSearch = false }
            )
        }
        .sheet(isPresented: $showingGoTo) {
            GoToPaletteView(
                onGo: { selection in
                    showingGoTo = false
                    sidebarSelection = selection
                    // Carry on with the keyboard in the notes of the place just chosen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focusRequest = .list }
                },
                onClose: { showingGoTo = false }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .showGoTo)) { _ in
            showingGoTo = true
        }
        .onChange(of: sidebarSelection) { old, selection in
            // The Dashboard has two columns and the rest three, so the sidebar is rebuilt when moving
            // between them and loses the keyboard; give it back so the arrow keys keep working
            if (old == .dashboard) != (selection == .dashboard), sidebarHasFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focusRequest = .sidebar }
            }
            // A project or area opens on its own dashboard
            if selection.hasOwnDashboard {
                selectedNote = nil
            }
        }
        .onChange(of: selectedNote?.id) { _, newID in
            // The dashboard hides the editor, so picking or creating a note must leave it
            if newID != nil, sidebarSelection == .dashboard {
                sidebarSelection = .all
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .escapeInMainWindow)) { notification in
            if sidebarSelection != .dashboard {
                sidebarSelection = .dashboard
            } else {
                // Hide rather than close so the window comes back as it was
                (notification.object as? NSWindow)?.orderOut(nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showGlobalSearch)) { _ in
            AppRouter.pendingSearch = false
            showingSearch = true
        }
        .onAppear {
            if AppRouter.pendingSearch {
                AppRouter.pendingSearch = false
                showingSearch = true
            }
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
                NoteListView(selectedCategory: sidebarSelection, selectedNote: $selectedNote,
                             focusRequest: $focusRequest, sidebarHasFocus: sidebarHasFocus, onMoveLeft: moveToSidebar)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
            } detail: {
                detailView
            }
        }
    }

    private var sidebar: some View {
        SidebarView(selection: $sidebarSelection, focusRequest: $focusRequest, hasFocus: $sidebarHasFocus, onMoveRight: { focusRequest = .list },
                    onDropNote: dropNote)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }

    /// A note dragged from the list onto a project or the Inbox moves there, and ⌘Z moves it back.
    private func dropNote(_ id: UUID, on selection: SidebarSelection) -> Bool {
        guard let place = NoteDrag.destination(for: selection),
              let note = storageManager.notes.first(where: { $0.id == id }),
              note.categoryType != place.category || note.targetName != place.targetName else { return false }
        let (oldCategory, oldTarget) = (note.categoryType, note.targetName)
        storageManager.move(note: note, to: place.category, targetName: place.targetName)
        undoManager?.registerUndo(withTarget: storageManager) { manager in
            if let current = manager.notes.first(where: { $0.id == id }) {
                manager.move(note: current, to: oldCategory, targetName: oldTarget)
            }
        }
        undoManager?.setActionName("Move Note")
        // The open note is the moved one: show it as it is now, in its new folder
        if selectedNote?.id == id { selectedNote = storageManager.notes.first { $0.id == id } }
        return true
    }

    /// Left arrow from the notes: to the project list, on the note's own project when All Notes is open
    private func moveToSidebar() {
        if sidebarSelection == .all, let note = selectedNote, note.categoryType == .project, let name = note.targetName {
            sidebarSelection = .project(name: name)
        }
        focusRequest = .sidebar
    }

    @ViewBuilder
    private var detailView: some View {
        if sidebarSelection == .dashboard {
            DashboardView { note in
                selectedNote = note
                sidebarSelection = .all
            }
        } else if sidebarSelection.hasOwnDashboard && selectedNote == nil {
            DashboardView(scope: sidebarSelection) { note in
                selectedNote = note
            }
            .id(sidebarSelection)
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
                Text("Press \(settings.quickCaptureShortcut.displayString) anywhere to capture a quick note")
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
        if let selected = selectedNote {
            // The stored note, so a renamed title shows
            let note = storageManager.notes.first { $0.id == selected.id } ?? selected
            return "\(note.displayTitle) — \(sidebarSelection.title)"
        }
        if sidebarSelection.hasOwnDashboard {
            return "\(sidebarSelection.title) Dashboard"
        }
        return sidebarSelection.title
    }
}
