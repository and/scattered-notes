import SwiftUI

public struct QuickCaptureView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    @ObservedObject var settings = AppSettings.shared
    var onDismiss: () -> Void
    
    @State private var noteContent: String = ""
    /// The project picked from the menu; a `+project` in the text takes precedence
    @State private var pickedProject: String?
    @State private var showingNewProjectDialog: Bool = false
    /// The note saved so far while auto-saving, finished when the panel closes
    @State private var draft: Note?
    @State private var autoSaveTimer: Timer?
    @FocusState private var isEditorFocused: Bool
    
    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    /// The project the note goes to: a `+project` in the text, else the one picked from the menu.
    /// The name can be new; the project is created when the note is filed.
    private var destination: String? {
        Self.inlineProject(in: noteContent, projects: storageManager.projects) ?? pickedProject
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Compact, Elegant Header: Single Destination Pill & Close
            HStack {
                Menu {
                    Button(action: { pickedProject = nil }) {
                        Label("Inbox", systemImage: "tray.fill")
                    }
                    
                    if !storageManager.projects.isEmpty {
                        Divider()
                        Section("Projects") {
                            ForEach(storageManager.projects) { proj in
                                Button(action: { pickedProject = proj.name }) {
                                    Label(proj.name, systemImage: proj.iconName)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    Button(action: { showingNewProjectDialog = true }) {
                        Label("New Project...", systemImage: "folder.badge.plus")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: destination == nil ? "tray.fill" : "folder.fill")
                            .font(.system(size: 12))
                            .foregroundColor(destinationColor)
                        Text(destination ?? "Inbox")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(destinationColor)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.wcagSecondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.wcagBadgeBackground)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(destinationColor.opacity(0.3), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                
                Spacer()
                
                Button(action: { onDismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.wcagSecondaryText)
                }
                .buttonStyle(.plain)
                .help(settings.quickNoteAutoSave ? "Done" : "Close without saving")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            Divider()
                .opacity(0.35)
            
            // Text Editor Area (Precisely Aligned Cursor & Placeholder)
            ZStack(alignment: .topLeading) {
                if noteContent.isEmpty {
                    Text("Type a quick note, thought, or checklist...\nTip: +project files it in a project, #tag tags it, @name mentions a person.")
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .foregroundColor(.wcagPlaceholderText)
                        .padding(.leading, 21)
                        .padding(.top, 14)
                        .padding(.trailing, 16)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $noteContent)
                    .accessibilityIdentifier("quickNoteText")
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .focused($isEditorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .onChange(of: noteContent) { _, _ in
                        scheduleAutoSave()
                    }
            }
            .frame(minHeight: 250, maxHeight: .infinity)
            
            Divider()
                .opacity(0.4)
            
            // Bottom Action & Shortcut Bar
            HStack {
                HStack(spacing: 12) {
                    ShortcutBadge(key: "Esc", label: settings.quickNoteAutoSave ? "Done" : "Discard")
                    ShortcutBadge(key: "+project", label: "File")
                    ShortcutBadge(key: "#tag", label: "Tag")
                    if !settings.quickNoteAutoSave {
                        ShortcutBadge(key: "⌘ Enter", label: "Save")
                    }
                }
                
                Spacer()
                
                if settings.quickNoteAutoSave {
                    autoSaveStatus
                } else {
                    Button(action: { saveNote() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Save Note")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isBlank ? Color.wcagBorder.opacity(0.3) : Color.wcagBlue)
                        .foregroundColor(isBlank ? Color.wcagSecondaryText : Color.white)
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(isBlank)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
        }
        .frame(minWidth: 660, minHeight: 390)
        .onAppear {
            isEditorFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: QuickCapturePanel.willHideNotification)) { _ in
            panelWillHide()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            // Quitting with Quick Note open files the note as closing it would
            panelWillHide()
        }
        .sheet(isPresented: $showingNewProjectDialog) {
            NewProjectAreaSheet(type: .project) { createdName, selectedIcon in
                storageManager.createProject(name: createdName, icon: selectedIcon)
                pickedProject = createdName
            }
        }
    }

    private var isBlank: Bool {
        noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var destinationColor: Color {
        destination == nil ? .wcagOrange : .wcagPurple
    }

    /// "Saved" once what is on screen is on disk, "Saving…" while a save is pending
    @ViewBuilder
    private var autoSaveStatus: some View {
        if draft != nil || autoSaveTimer != nil {
            let pending = autoSaveTimer != nil
            Label(pending ? "Saving…" : "Saved to \(draft?.destinationDisplay ?? "Inbox")",
                  systemImage: pending ? "ellipsis.circle" : "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(pending ? .wcagSecondaryText : .wcagGreen)
                .help("Quick Note saves as you type. Close it or press Esc when you're done.")
                .accessibilityIdentifier("quickNoteStatus")
        } else {
            Text("Saves as you type")
                .font(.system(size: 12))
                .foregroundColor(.wcagSecondaryText)
        }
    }

    // MARK: - Saving

    private func scheduleAutoSave() {
        guard settings.quickNoteAutoSave else { return }
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            Task { @MainActor in
                autoSaveTimer = nil
                autoSave()
            }
        }
    }

    /// Writes what has been typed so far, as it stands. A `+project` in the text is only applied
    /// when the panel closes, so a half-typed name never creates a project.
    private func autoSave() {
        guard !isBlank || draft != nil else { return }
        if var note = draft {
            note.content = noteContent
            note.tags = Note.tags(in: noteContent)
            storageManager.save(note: note)
            draft = storageManager.notes.first { $0.id == note.id } ?? note
        } else {
            let project = pickedProject.flatMap { name in storageManager.projects.first { $0.name == name }?.name }
            draft = storageManager.createNote(
                content: noteContent,
                category: project == nil ? .inbox : .project,
                targetName: project,
                tags: Note.tags(in: noteContent)
            )
        }
    }

    private func panelWillHide() {
        if settings.quickNoteAutoSave {
            autoSaveTimer?.invalidate()
            autoSaveTimer = nil
            if let note = draft {
                if isBlank {
                    // Everything typed was deleted again
                    storageManager.delete(note: storageManager.notes.first { $0.id == note.id } ?? note)
                } else {
                    file(content: noteContent, replacing: storageManager.notes.first { $0.id == note.id } ?? note)
                }
            } else if !isBlank {
                file(content: noteContent, replacing: nil)
            }
        }
        // In manual mode, closing throws away what wasn't saved
        reset()
    }

    private func saveNote() {
        guard !isBlank else { return }
        file(content: noteContent, replacing: nil)
        reset()
        onDismiss()
    }

    /// Files the note in its destination, creating a new project if needed, without the
    /// `+project` mark. Updates `existing` when auto-save already wrote the note.
    private func file(content: String, replacing existing: Note?) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = destination
        if let project, !storageManager.projects.contains(where: { $0.name.caseInsensitiveCompare(project) == .orderedSame }) {
            storageManager.createProject(name: project)
        }
        let cleaned = Note.removeProjectTag(from: trimmed, targetName: project)
        let finalContent = cleaned.isEmpty ? (project ?? trimmed) : cleaned
        let category: CategoryType = project == nil ? .inbox : .project

        if var note = existing {
            note.content = finalContent
            note.tags = Note.tags(in: finalContent)
            note.categoryType = category
            note.targetName = project
            storageManager.save(note: note)
        } else {
            storageManager.createNote(
                content: finalContent,
                category: category,
                targetName: project,
                tags: Note.tags(in: finalContent)
            )
        }
    }

    private func reset() {
        noteContent = ""
        pickedProject = nil
        draft = nil
    }

    /// The project named by the first `+project`, `p:project` or `[[project]]` in `text`: an
    /// existing project's spelling when the name matches one, ignoring case and spaces, else the
    /// name as typed with a capital first letter.
    static func inlineProject(in text: String, projects: [ProjectArea]) -> String? {
        let name: String
        if let open = text.range(of: "[["),
           let close = text.range(of: "]]", range: open.upperBound..<text.endIndex),
           case let inside = text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces),
           !inside.isEmpty {
            name = inside
        } else if let mark = Mentions.marks(in: text).first(where: { $0.kind == .project }) {
            name = mark.name
        } else if let word = text.split(whereSeparator: \.isWhitespace).first(where: { $0.hasPrefix("p:") && $0.count > 2 }) {
            name = String(word.dropFirst(2)).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        } else {
            return nil
        }
        guard !name.isEmpty else { return nil }
        let squashed = name.replacingOccurrences(of: " ", with: "").lowercased()
        if let match = projects.first(where: {
            $0.name.lowercased() == name.lowercased() || $0.name.replacingOccurrences(of: " ", with: "").lowercased() == squashed
        }) {
            return match.name
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

public struct ShortcutBadge: View {
    let key: String
    let label: String
    
    public var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.wcagBorder, lineWidth: 1))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.wcagSecondaryText)
        }
    }
}

public struct NewProjectAreaSheet: View {
    let type: CategoryType
    let onCreated: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedIcon: String = "folder.fill"
    
    private let availableIcons = [
        "folder.fill", "briefcase.fill", "rocket.fill", "star.fill",
        "lightbulb.fill", "laptopcomputer", "hammer.fill", "chart.bar.fill",
        "cart.fill", "book.fill", "heart.fill", "checkmark.seal.fill"
    ]
    
    public init(type: CategoryType, onCreated: @escaping (String, String) -> Void) {
        self.type = type
        self.onCreated = onCreated
        self._selectedIcon = State(initialValue: type == .project ? "folder.fill" : "square.stack.3d.up.fill")
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            Text("Create New \(type == .project ? "Project" : "Area")")
                .font(.headline)
            
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose Icon")
                    .font(.caption)
                    .foregroundColor(.wcagSecondaryText)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button(action: { selectedIcon = icon }) {
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .frame(width: 36, height: 36)
                                .background(selectedIcon == icon ? Color.wcagBlue.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                                .foregroundColor(selectedIcon == icon ? .wcagBlue : .wcagSecondaryText)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedIcon == icon ? Color.wcagBlue : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 280)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Create") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onCreated(trimmed, selectedIcon)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 330)
    }
}
