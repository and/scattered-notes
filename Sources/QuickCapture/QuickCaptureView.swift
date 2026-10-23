import SwiftUI

public struct QuickCaptureView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    var onDismiss: () -> Void
    
    @State private var noteContent: String = ""
    @State private var selectedDestination: DestinationOption = .inbox
    @State private var showingNewProjectDialog: Bool = false
    @State private var newProjectName: String = ""
    @State private var newCategoryType: CategoryType = .project
    @FocusState private var isEditorFocused: Bool
    
    public enum DestinationOption: Hashable {
        case inbox
        case project(name: String)
        case area(name: String)
        
        var displayName: String {
            switch self {
            case .inbox: return "Inbox"
            case .project(let name): return name
            case .area(let name): return name
            }
        }
        
        var iconName: String {
            switch self {
            case .inbox: return "tray.fill"
            case .project: return "folder.fill"
            case .area: return "square.stack.3d.up.fill"
            }
        }
        
        var categoryType: CategoryType {
            switch self {
            case .inbox: return .inbox
            case .project: return .project
            case .area: return .area
            }
        }
        
        var targetName: String? {
            switch self {
            case .inbox: return nil
            case .project(let name): return name
            case .area(let name): return name
            }
        }
    }
    
    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar: Destination Pill Picker & Status
            HStack {
                Menu {
                    Button(action: { selectedDestination = .inbox }) {
                        Label("Inbox", systemImage: "tray.fill")
                    }
                    
                    if !storageManager.projects.isEmpty {
                        Divider()
                        Section("Projects") {
                            ForEach(storageManager.projects) { proj in
                                Button(action: { selectedDestination = .project(name: proj.name) }) {
                                    Label(proj.name, systemImage: "folder.fill")
                                }
                            }
                        }
                    }
                    
                    if !storageManager.areas.isEmpty {
                        Divider()
                        Section("Areas") {
                            ForEach(storageManager.areas) { area in
                                Button(action: { selectedDestination = .area(name: area.name) }) {
                                    Label(area.name, systemImage: "square.stack.3d.up.fill")
                                }
                            }
                        }
                    }
                    
                    Divider()
                    Button(action: {
                        newCategoryType = .project
                        showingNewProjectDialog = true
                    }) {
                        Label("New Project...", systemImage: "plus")
                    }
                    Button(action: {
                        newCategoryType = .area
                        showingNewProjectDialog = true
                    }) {
                        Label("New Area...", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedDestination.iconName)
                            .foregroundColor(.accentColor)
                        Text(selectedDestination.displayName)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
                
                Spacer()
                
                Text("Quick Capture")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { onDismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider()
                .opacity(0.4)
            
            // Quick Project Suggestion / Tagging Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Destination:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                    
                    Button(action: { selectedDestination = .inbox }) {
                        HStack(spacing: 4) {
                            Image(systemName: "tray.fill")
                                .font(.system(size: 10))
                            Text("Inbox")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(selectedDestination == .inbox ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                        .foregroundColor(selectedDestination == .inbox ? .accentColor : .primary)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedDestination == .inbox ? Color.accentColor : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    
                    ForEach(storageManager.projects) { proj in
                        Button(action: { selectedDestination = .project(name: proj.name) }) {
                            HStack(spacing: 4) {
                                Image(systemName: proj.iconName)
                                    .font(.system(size: 10))
                                Text(proj.name)
                                    .font(.system(size: 11))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(selectedDestination == .project(name: proj.name) ? Color.purple.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                            .foregroundColor(selectedDestination == .project(name: proj.name) ? .purple : .primary)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedDestination == .project(name: proj.name) ? Color.purple : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    ForEach(storageManager.areas) { area in
                        Button(action: { selectedDestination = .area(name: area.name) }) {
                            HStack(spacing: 4) {
                                Image(systemName: area.iconName)
                                    .font(.system(size: 10))
                                Text(area.name)
                                    .font(.system(size: 11))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(selectedDestination == .area(name: area.name) ? Color.green.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                            .foregroundColor(selectedDestination == .area(name: area.name) ? .green : .primary)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedDestination == .area(name: area.name) ? Color.green : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // If inline detection found a new candidate project not yet created
                    if case .project(let name) = selectedDestination,
                       !storageManager.projects.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text("New: \(name)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.3))
                        .foregroundColor(.purple)
                        .cornerRadius(6)
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 12)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            
            Divider()
                .opacity(0.3)
            
            // Text Editor Area
            ZStack(alignment: .topLeading) {
                if noteContent.isEmpty {
                    Text("Type a quick note, thought, or checklist...\nTip: Type +Project, @Project, or [[Project]] to assign to a project inline.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $noteContent)
                    .font(.system(size: 15))
                    .focused($isEditorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .onChange(of: noteContent) { _, newText in
                        detectInlineProjectTag(in: newText)
                    }
            }
            .frame(minHeight: 180, maxHeight: .infinity)
            
            Divider()
                .opacity(0.4)
            
            // Bottom Action & Shortcut Bar
            HStack {
                HStack(spacing: 12) {
                    ShortcutBadge(key: "Esc", label: "Close")
                    ShortcutBadge(key: "+Project", label: "Tag")
                    ShortcutBadge(key: "⌘ Enter", label: "Save")
                }
                
                Spacer()
                
                Button(action: { saveNote() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Save Note")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
        }
        .frame(minWidth: 580, minHeight: 300)
        .onAppear {
            isEditorFocused = true
        }
        .sheet(isPresented: $showingNewProjectDialog) {
            NewProjectAreaSheet(type: newCategoryType) { createdName, selectedIcon in
                if newCategoryType == .project {
                    storageManager.createProject(name: createdName, icon: selectedIcon)
                    selectedDestination = .project(name: createdName)
                } else {
                    storageManager.createArea(name: createdName, icon: selectedIcon)
                    selectedDestination = .area(name: createdName)
                }
            }
        }
    }
    
    private func saveNote() {
        let trimmed = noteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Auto-create destination project/area if specified inline but doesn't exist yet
        if selectedDestination.categoryType == .project, let pName = selectedDestination.targetName {
            if !storageManager.projects.contains(where: { $0.name.lowercased() == pName.lowercased() }) {
                storageManager.createProject(name: pName)
            }
        } else if selectedDestination.categoryType == .area, let aName = selectedDestination.targetName {
            if !storageManager.areas.contains(where: { $0.name.lowercased() == aName.lowercased() }) {
                storageManager.createArea(name: aName)
            }
        }
        
        // Extract tags (words starting with # that aren't the project name)
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines)
        let extractedTags = words
            .filter { $0.hasPrefix("#") && $0.count > 1 }
            .map { String($0.dropFirst()).trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty && $0.lowercased() != selectedDestination.targetName?.lowercased() }
        
        storageManager.createNote(
            title: "",
            content: trimmed,
            category: selectedDestination.categoryType,
            targetName: selectedDestination.targetName,
            tags: extractedTags
        )
        
        noteContent = ""
        onDismiss()
    }
    
    private func detectInlineProjectTag(in text: String) {
        // Check for [[ProjectName]] wiki-links
        if let wikiRangeStart = text.range(of: "[["),
           let wikiRangeEnd = text.range(of: "]]", range: wikiRangeStart.upperBound..<text.endIndex) {
            let inside = String(text[wikiRangeStart.upperBound..<wikiRangeEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !inside.isEmpty {
                applyDestination(from: inside)
                return
            }
        }
        
        // Check words for +Project, @Project, p:Project, or matching #Project
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            var candidate = ""
            var isExplicitProjectPrefix = false
            
            if word.hasPrefix("+") && word.count > 1 {
                candidate = String(word.dropFirst())
                isExplicitProjectPrefix = true
            } else if word.hasPrefix("@") && word.count > 1 {
                candidate = String(word.dropFirst())
                isExplicitProjectPrefix = true
            } else if word.hasPrefix("p:") && word.count > 2 {
                candidate = String(word.dropFirst(2))
                isExplicitProjectPrefix = true
            } else if word.hasPrefix("#") && word.count > 1 {
                candidate = String(word.dropFirst())
            }
            
            guard !candidate.isEmpty else { continue }
            let cleaned = candidate.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !cleaned.isEmpty else { continue }
            
            // 1. Check if matches an existing project
            if let matchedProject = storageManager.projects.first(where: {
                $0.name.lowercased() == cleaned.lowercased() ||
                $0.name.replacingOccurrences(of: " ", with: "").lowercased() == cleaned.lowercased()
            }) {
                selectedDestination = .project(name: matchedProject.name)
                return
            }
            
            // 2. Check if matches an existing area
            if let matchedArea = storageManager.areas.first(where: {
                $0.name.lowercased() == cleaned.lowercased() ||
                $0.name.replacingOccurrences(of: " ", with: "").lowercased() == cleaned.lowercased()
            }) {
                selectedDestination = .area(name: matchedArea.name)
                return
            }
            
            // 3. If explicit prefix like +ProjectName or @ProjectName, treat as a new project target!
            if isExplicitProjectPrefix && cleaned.count >= 2 {
                // Capitalize first letter nicely
                let formattedName = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
                selectedDestination = .project(name: formattedName)
                return
            }
        }
    }
    
    private func applyDestination(from rawName: String) {
        let cleaned = rawName.trimmingCharacters(in: .whitespaces)
        if let matchedProject = storageManager.projects.first(where: {
            $0.name.lowercased() == cleaned.lowercased()
        }) {
            selectedDestination = .project(name: matchedProject.name)
        } else if let matchedArea = storageManager.areas.first(where: {
            $0.name.lowercased() == cleaned.lowercased()
        }) {
            selectedDestination = .area(name: matchedArea.name)
        } else if !cleaned.isEmpty {
            selectedDestination = .project(name: cleaned)
        }
    }
}

public struct ShortcutBadge: View {
    let key: String
    let label: String
    
    public var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button(action: { selectedIcon = icon }) {
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .frame(width: 36, height: 36)
                                .background(selectedIcon == icon ? Color.accentColor.opacity(0.25) : Color(NSColor.controlBackgroundColor))
                                .foregroundColor(selectedIcon == icon ? .accentColor : .secondary)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedIcon == icon ? Color.accentColor : Color.clear, lineWidth: 1.5)
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
