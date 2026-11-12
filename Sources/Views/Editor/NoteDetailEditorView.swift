import SwiftUI
import Combine

public struct NoteDetailEditorView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var suggestions = SuggestionEngine.shared
    
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
    /// Off to begin with: most notes have no links, and the column takes room from the text
    @AppStorage("showLinksPanel") private var showLinksPanel = false
    
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
            // Agenda above Links in one column, so the window keeps three columns however many are open
            if showsAgenda || showsLinks {
                Divider()
                rightColumn
            }
        }
    }

    /// Height Links keeps when Agenda is open too; dragged with the bar between them, and remembered
    @AppStorage("linksPanelHeight") private var linksPanelHeight = 340.0
    @State private var linksHeightAtDragStart: Double?

    private var rightColumn: some View {
        GeometryReader { geo in
            let both = showsAgenda && showsLinks
            let handle: CGFloat = 9
            let minimum: CGFloat = 90
            let links = min(max(CGFloat(linksPanelHeight), minimum), max(minimum, geo.size.height - minimum - handle))
            VStack(spacing: 0) {
                if showsAgenda {
                    agendaPanel.frame(height: both ? geo.size.height - links - handle : nil)
                }
                if both {
                    PaneResizeHandle()
                        .frame(height: handle)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = linksHeightAtDragStart ?? Double(links)
                                linksHeightAtDragStart = start
                                // Dragging the bar up gives Links more room
                                linksPanelHeight = min(max(start - Double(drag.translation.height), Double(minimum)),
                                                       Double(max(minimum, geo.size.height - minimum - handle)))
                            }
                            .onEnded { _ in linksHeightAtDragStart = nil })
                        .onTapGesture(count: 2) { linksPanelHeight = 340 }
                }
                if showsLinks {
                    linksPanel.frame(height: both ? links : nil)
                }
            }
        }
        // The panels have their own width; this keeps the column from growing past it
        .frame(width: 240)
    }

    private var agendaPanel: some View {
        AgendaInspectorView(
            items: agendaItems,
            onToggle: { item in
                // Edit the live text so the toggle is not overwritten by the next autosave
                editableContent = Note.togglingChecklistLine(item.lineIndex, in: editableContent)
                scheduleSave()
            },
            history: { storageManager.dateHistory(for: $0) },
            onSetDate: { item, day in
                // Same for the day: write it into the live text, then log it
                let day = Calendar.current.startOfDay(for: day)
                guard item.date != day,
                      let key = AgendaExtractor.lineKey(onLine: item.lineIndex, in: editableContent) else { return }
                editableContent = AgendaExtractor.settingDate(day, onLine: item.lineIndex, in: editableContent)
                storageManager.logDateChange(noteID: note.id, lineText: key, from: item.date, to: day)
                scheduleSave()
            }
        )
    }

    /// The Links column shows only when it is turned on and the note has something to list
    private var showsLinks: Bool { showLinksPanel && linksPanel.hasContent }

    private var linksPanel: NoteLinksPanel {
        NoteLinksPanel(
            noteID: note.id,
            index: storageManager.linkIndex,
            related: storageManager.relatedIndex,
            notes: Dictionary(storageManager.notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            suggested: settings.suggestNotes ? suggestions.index : nil,
            onMakeLink: makeLink
        )
    }

    /// Writes `[[Title]]` over the first plain mention of that note, in the text as it is now (the Links column
    /// reads the saved text, which may be a moment behind). Done through the text view so ⌘Z undoes it.
    private func makeLink(to targetID: UUID) {
        guard let target = storageManager.notes.first(where: { $0.id == targetID }) else { return }
        var notes = storageManager.notes
        if let mine = notes.firstIndex(where: { $0.id == note.id }) { notes[mine].content = editableContent }
        guard let link = NoteLinkIndex(notes: notes).links(from: note.id).first(where: { $0.target == targetID && !$0.isExplicit }),
              let replacement = NoteLinkIndex.explicitText(forTitle: target.displayTitle) else { return }
        if !EditorFocus.replaceText(in: link.range, with: replacement, showing: editableContent),
           let changed = NoteLinkIndex.makingExplicit(link, title: target.displayTitle, in: editableContent) {
            // The text view is not showing (preview mode): change the text directly
            editableContent = changed
            scheduleSave()
        }
    }

    /// Keeps the meaning vectors of the notes up to date while suggestions are on and the column is open
    private func updateSuggestions() {
        guard showLinksPanel, settings.suggestNotes else { return }
        suggestions.update(with: storageManager.notes)
    }

    /// A log note (its title or its first line starts with "Log -") is edited in a monospaced font, with a time at the start of each line
    private var isLogNote: Bool { LogLines.isLog(title: editableTitle, content: editableContent) }

    /// The place text is typed into: the log editor for a log note, the plain one for the rest
    @ViewBuilder
    private var textPane: some View {
        Group {
            if isLogNote {
                LogEditorView(content: $editableContent, fontSize: CGFloat(settings.editorFontSize))
            } else {
                TextEditor(text: $editableContent)
                    .accessibilityIdentifier("noteText")
                    .font(.system(size: CGFloat(settings.editorFontSize)))
                    .lineSpacing(4)
                    .padding(16)
                    .scrollContentBackground(.hidden)
            }
        }
        .onChange(of: editableContent) { _, newContent in
            if newContent != note.content {
                scheduleSave()
            }
        }
        .onChange(of: isLogNote) { _, _ in
            // Typing "Log -" swaps the editor, which loses the cursor: put it back where it was. Typing in the
            // title field also gets here, and the cursor stays there.
            if let field = NSApp.keyWindow?.firstResponder as? NSTextView, field.isFieldEditor { return }
            let place = settings.lastPlace
            var offset = place?.noteID == note.id ? place?.offset : nil
            // The saved place is one keystroke behind: the cursor is just after the dash that made it a log
            if isLogNote, let end = LogLines.headingEnd(in: editableContent) { offset = max(offset ?? 0, end) }
            EditorFocus.request(noteID: note.id, offset: offset)
        }
    }

    private var showsAgenda: Bool { showAgendaInspector && !agendaItems.isEmpty }

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
                
                // Links column toggle
                Button(action: { showLinksPanel.toggle() }) {
                    Image(systemName: "link")
                        .foregroundColor(showLinksPanel ? .wcagBlue : .wcagSecondaryText)
                }
                .buttonStyle(.plain)
                .help(showLinksPanel ? "Hide Links" : "Show Links")
                .accessibilityIdentifier("linksToggle")
                
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
            .frame(height: PaneHeader.height)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
            
            Divider()
            
            // Content Area based on Editor Mode
            GeometryReader { _ in
                switch editorMode {
                case .edit:
                    textPane

                case .split:
                    HStack(spacing: 0) {
                        textPane
                        
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
        .onReceive(storageManager.$notes) { _ in updateSuggestions() }
        .onChange(of: showLinksPanel) { _, _ in updateSuggestions() }
        .onChange(of: settings.suggestNotes) { _, _ in updateSuggestions() }
        .onAppear {
            updateSuggestions()
            EditorFocus.openNoteID = note.id
            syncFromNote()
            focusEditorIfRequested()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusNoteEditor)) { _ in
            focusEditorIfRequested()
        }
        .onDisappear {
            if EditorFocus.openNoteID == note.id { EditorFocus.openNoteID = nil }
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
                let id = note.id
                storageManager.delete(note: note)
                // The editor falls back to the note it opened with, so the window must close it
                NotificationCenter.default.post(name: .noteDeleted, object: nil, userInfo: ["id": id])
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
        EditorFocus.focusTextView(showing: text, atOffset: request.offset ?? EditorFocus.cursorOffset(in: text, terms: request.terms))
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
    
    /// What a note with no title of its own is called: its first line
    private func firstLineTitle(of content: String) -> String {
        Note(title: "", content: content, createdAt: Date(), updatedAt: Date()).displayTitle
    }

    /// A note whose title was never typed by hand, a new "Untitled Note" or one named after its first line,
    /// keeps being named after its first line as that is edited. A title typed in the header is left alone.
    private func followFirstLine() {
        guard editableTitle == note.title,
              note.title.isEmpty || note.title == "Untitled Note" || note.title == firstLineTitle(of: note.content) else { return }
        let derived = firstLineTitle(of: editableContent)
        if derived != editableTitle { editableTitle = derived }
    }

    private func saveNow() {
        followFirstLine()
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
