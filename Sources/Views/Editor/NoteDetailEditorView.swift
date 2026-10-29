import SwiftUI
import Combine

public struct NoteDetailEditorView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    @ObservedObject var settings = AppSettings.shared
    
    /// The note as it was when opened; it only says which note this is
    private let opened: Note
    /// The note as stored now. Moves, pins, saves and edits from other devices all change it, so the
    /// editor always works from this one, never from the copy it was opened with
    private var note: Note { storageManager.notes.first { $0.id == opened.id } ?? opened }
    
    @State private var editableTitle: String
    @State private var editableContent: String
    /// The title and text last loaded from or saved to the note. While the fields still match them,
    /// nothing was typed since, so a newer version from another device can replace them
    @State private var syncedTitle: String
    @State private var syncedContent: String
    @State private var editorMode: EditorMode = .edit
    @State private var saveDebounceTimer: Timer?
    @State private var showingDeleteAlert = false
    @AppStorage("showAgendaInspector") private var showAgendaInspector = true
    
    public enum EditorMode: String, CaseIterable {
        case edit = "Edit"
        case split = "Split"
        case preview = "Preview"
        
        var iconName: String {
            switch self {
            case .edit: return "square.and.pencil"
            case .split: return "rectangle.split.2x1"
            case .preview: return "eye"
            }
        }
    }
    
    public init(note: Note) {
        self.opened = note
        self._editableTitle = State(initialValue: note.title)
        self._editableContent = State(initialValue: note.content)
        self._syncedTitle = State(initialValue: note.title)
        self._syncedContent = State(initialValue: note.content)
    }
    
    private var currentDestinationIcon: String {
        switch note.categoryType {
        case .inbox:
            return "tray.fill"
        case .project:
            if let name = note.targetName, let proj = storageManager.projects.first(where: { $0.name == name }) {
                return proj.iconName
            }
            return "folder.fill"
        case .area:
            // Only until the note is moved out of its old area, which happens as notes load
            return "tray.fill"
        }
    }
    
    private var destinationColor: Color {
        switch note.categoryType {
        case .inbox: return .wcagOrange
        case .project: return .wcagPurple
        case .area: return .wcagOrange
        }
    }
    
    /// Agenda lines of the saved note; empty when the note has none
    private var agendaItems: [AgendaItem] {
        storageManager.agendaItems(for: note)
    }

    public var body: some View {
        HStack(spacing: 0) {
            editorColumn
            if showAgendaInspector, !agendaItems.isEmpty {
                Divider()
                AgendaInspectorView(items: agendaItems) { item in
                    // Edit the live text so the toggle is not overwritten by the next autosave
                    editableContent = Note.togglingChecklistLine(item.lineIndex, in: editableContent)
                    scheduleSave()
                }
            }
        }
    }

    private var editorColumn: some View {
        VStack(spacing: 0) {
            // Header: Title, Category Picker, Actions
            HStack(spacing: 12) {
                TextField("Note Title", text: $editableTitle)
                    .accessibilityIdentifier("noteTitle")
                    .font(.system(size: 18, weight: .semibold))
                    .textFieldStyle(.plain)
                    .onChange(of: editableTitle) { _, newTitle in
                        if newTitle != note.title {
                            scheduleSave()
                        }
                    }
                
                Spacer()
                
                // Destination / Project Selector Menu
                Menu {
                    Button(action: { moveTo(category: .inbox, target: nil) }) {
                        Label("Inbox", systemImage: "tray.fill")
                    }
                    
                    if !storageManager.projects.isEmpty {
                        Divider()
                        Section("Projects") {
                            ForEach(storageManager.projects) { proj in
                                Button(action: { moveTo(category: .project, target: proj.name) }) {
                                    Label(proj.name, systemImage: proj.iconName)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: currentDestinationIcon)
                            .foregroundColor(destinationColor)
                        Text(note.destinationDisplay)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(destinationColor)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.wcagSecondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.wcagBadgeBackground)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(destinationColor.opacity(0.3), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier("noteDestination")
                
                // Mode Picker (Edit / Split / Preview)
                Picker("", selection: $editorMode) {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                
                // Agenda column toggle, only for notes that have agenda lines
                if !agendaItems.isEmpty {
                    Button(action: { showAgendaInspector.toggle() }) {
                        Image(systemName: "sidebar.right")
                            .foregroundColor(showAgendaInspector ? .wcagBlue : .wcagSecondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(showAgendaInspector ? "Hide Agenda" : "Show Agenda")
                }
                
                // Pin Button
                Button(action: {
                    storageManager.togglePin(note: note)
                }) {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                        .foregroundColor(note.isPinned ? .wcagOrange : .wcagSecondaryText)
                }
                .buttonStyle(.plain)
                .help(note.isPinned ? "Unpin Note" : "Pin Note")
                
                // Reveal in Finder
                if let path = note.filePath {
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([path])
                    }) {
                        Image(systemName: "folder")
                            .foregroundColor(.wcagSecondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal file in Finder")
                }
                
                // Delete Button
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.wcagSecondaryText)
                }
                .buttonStyle(.plain)
                .help("Delete Note")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
            
            Divider()
            
            // Content Area based on Editor Mode
            GeometryReader { _ in
                switch editorMode {
                case .edit:
                    TextEditor(text: $editableContent)
                        .accessibilityIdentifier("noteText")
                        .font(.system(size: CGFloat(settings.editorFontSize)))
                        .lineSpacing(4)
                        .padding(16)
                        .scrollContentBackground(.hidden)
                        .onChange(of: editableContent) { _, newContent in
                            if newContent != note.content {
                                scheduleSave()
                            }
                        }
                    
                case .split:
                    HStack(spacing: 0) {
                        TextEditor(text: $editableContent)
                            .font(.system(size: CGFloat(settings.editorFontSize)))
                            .lineSpacing(4)
                            .padding(16)
                            .scrollContentBackground(.hidden)
                            .onChange(of: editableContent) { _, newContent in
                                if newContent != note.content {
                                    scheduleSave()
                                }
                            }
                        
                        Divider()
                        
                        MarkdownRendererView(content: $editableContent) { _ in
                            scheduleSave()
                        }
                    }
                    
                case .preview:
                    MarkdownRendererView(content: $editableContent) { _ in
                        scheduleSave()
                    }
                }
            }
            
            Divider()
            
            // Status bar at bottom
            HStack(spacing: 16) {
                if let stats = note.checklistStats {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                        Text("\(stats.completed)/\(stats.total) tasks")
                    }
                    .font(.caption)
                    .foregroundColor(stats.completed == stats.total ? .wcagGreen : .wcagSecondaryText)
                }
                
                Text("Last modified \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.wcagSecondaryText)
                
                Spacer()
                
                if !note.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(note.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.wcagBadgeBackground)
                                .foregroundColor(.wcagBlue)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.wcagBlue.opacity(0.3), lineWidth: 0.5))
                        }
                    }
                }
                
                Text("\(Self.wordCount(in: editableContent)) words")
                    .font(.caption)
                    .foregroundColor(.wcagSecondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        }
        .onAppear {
            syncFromNote()
            focusEditorIfRequested()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusNoteEditor)) { _ in
            focusEditorIfRequested()
        }
        .onDisappear {
            // Flush pending edits instead of dropping them, e.g. when switching to the dashboard
            flushPendingSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            flushPendingSave()
        }
        .onChange(of: note.id) { _, _ in
            syncFromNote()
        }
        .onChange(of: [note.title, note.content]) { _, _ in
            takeNewerVersion()
        }
        .alert("Delete Note?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                storageManager.delete(note: note)
            }
        } message: {
            Text("Are you sure you want to delete \"\(note.displayTitle)\"? This will remove the file from disk.")
        }
    }
    
    /// The number of words in `text`, counted by scanning it once, without splitting it into an array of words.
    static func wordCount(in text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    private func syncFromNote() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = nil
        if editableTitle != note.title {
            editableTitle = note.title
        }
        if editableContent != note.content {
            // The app may have written date markers into the text being typed; the cursor stays put
            EditorFocus.keepCursor(from: editableContent, to: note.content)
            editableContent = note.content
        }
        syncedTitle = note.title
        syncedContent = note.content
    }

    /// Shows a version of the note saved elsewhere, e.g. on the iPhone, unless something was typed
    /// here since the last save; then the typing wins when it is saved.
    private func takeNewerVersion() {
        guard saveDebounceTimer == nil, editableTitle == syncedTitle, editableContent == syncedContent else { return }
        syncFromNote()
    }
    
    /// Puts the cursor in the text when Enter was pressed on this note or it was opened from a search
    private func focusEditorIfRequested() {
        guard let request = EditorFocus.pending, request.noteID == note.id else { return }
        EditorFocus.pending = nil
        if editorMode == .preview { editorMode = .edit }
        let text = editableContent
        EditorFocus.focusTextView(showing: text, atOffset: EditorFocus.cursorOffset(in: text, terms: request.terms))
    }
    
    private func flushPendingSave() {
        guard saveDebounceTimer != nil else { return }
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = nil
        saveNow()
    }
    
    private func scheduleSave() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            saveDebounceTimer = nil
            saveNow()
        }
    }
    
    private func saveNow() {
        syncedTitle = editableTitle
        syncedContent = editableContent
        guard editableTitle != note.title || editableContent != note.content else { return }
        var updated = note
        updated.title = editableTitle
        updated.content = editableContent
        
        updated.tags = Note.tags(in: editableContent)
        
        storageManager.save(note: updated)
    }
    
    private func moveTo(category: CategoryType, target: String?) {
        // Typing not yet saved goes with the note
        flushPendingSave()
        storageManager.move(note: note, to: category, targetName: target)
    }
}
