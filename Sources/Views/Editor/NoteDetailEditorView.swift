import SwiftUI
import Combine

public struct NoteDetailEditorView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    @ObservedObject var settings = AppSettings.shared
    
    var note: Note
    
    @State private var editableTitle: String
    @State private var editableContent: String
    @State private var editorMode: EditorMode = .edit
    @State private var saveDebounceTimer: Timer?
    @State private var showingDeleteAlert = false
    
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
        self.note = note
        self._editableTitle = State(initialValue: note.title)
        self._editableContent = State(initialValue: note.content)
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
            if let name = note.targetName, let area = storageManager.areas.first(where: { $0.name == name }) {
                return area.iconName
            }
            return "square.stack.3d.up.fill"
        }
    }
    
    private var destinationColor: Color {
        switch note.categoryType {
        case .inbox: return .wcagOrange
        case .project: return .wcagPurple
        case .area: return .wcagGreen
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header: Title, Category Picker, Actions
            HStack(spacing: 12) {
                TextField("Note Title", text: $editableTitle)
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
                    
                    if !storageManager.areas.isEmpty {
                        Divider()
                        Section("Areas") {
                            ForEach(storageManager.areas) { area in
                                Button(action: { moveTo(category: .area, target: area.name) }) {
                                    Label(area.name, systemImage: area.iconName)
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
                
                // Mode Picker (Edit / Split / Preview)
                Picker("", selection: $editorMode) {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                
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
                
                Text("\(editableContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words")
                    .font(.caption)
                    .foregroundColor(.wcagSecondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
        }
        .onAppear {
            syncFromNote()
        }
        .onDisappear {
            saveDebounceTimer?.invalidate()
            saveDebounceTimer = nil
        }
        .onChange(of: note.id) { _, _ in
            syncFromNote()
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
    
    private func syncFromNote() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = nil
        if editableTitle != note.title {
            editableTitle = note.title
        }
        if editableContent != note.content {
            editableContent = note.content
        }
    }
    
    private func scheduleSave() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            guard editableTitle != note.title || editableContent != note.content else { return }
            var updated = note
            updated.title = editableTitle
            updated.content = editableContent
            
            // Re-extract tags
            let words = editableContent.components(separatedBy: .whitespacesAndNewlines)
            let tags = words
                .filter { $0.hasPrefix("#") && $0.count > 1 }
                .map { String($0.dropFirst()).trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
                .filter { !$0.isEmpty }
            if !tags.isEmpty {
                updated.tags = Array(Set(tags)).sorted()
            }
            
            storageManager.save(note: updated)
        }
    }
    
    private func moveTo(category: CategoryType, target: String?) {
        storageManager.move(note: note, to: category, targetName: target)
    }
}
