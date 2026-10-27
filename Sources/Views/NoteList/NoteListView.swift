import SwiftUI

public enum NoteSortOption: String, CaseIterable {
    case dateUpdated = "Date Modified"
    case dateCreated = "Date Created"
    case title = "Title"
}

public struct NoteListView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    
    var selectedCategory: SidebarSelection
    @Binding var selectedNote: Note?
    
    @State private var searchText: String = ""
    @State private var sortOption: NoteSortOption = .dateUpdated
    @FocusState private var listFocused: Bool
    
    public init(selectedCategory: SidebarSelection, selectedNote: Binding<Note?>) {
        self.selectedCategory = selectedCategory
        self._selectedNote = selectedNote
    }
    
    public var filteredNotes: [Note] {
        var result = storageManager.notes
        
        // 1. Filter by category/project
        switch selectedCategory {
        case .all, .dashboard:
            break
        case .inbox:
            result = result.filter { $0.categoryType == .inbox }
        case .project(let name):
            result = result.filter { $0.categoryType == .project && $0.targetName == name }
        case .area(let name):
            result = result.filter { $0.categoryType == .area && $0.targetName == name }
        }
        
        // 2. Filter by search text
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { note in
                note.title.lowercased().contains(query) ||
                note.content.lowercased().contains(query) ||
                note.tags.contains { $0.lowercased().contains(query) } ||
                (note.targetName?.lowercased().contains(query) ?? false)
            }
        }
        
        // 3. Sort
        result.sort { n1, n2 in
            if n1.isPinned != n2.isPinned {
                return n1.isPinned && !n2.isPinned
            }
            switch sortOption {
            case .dateUpdated:
                return n1.updatedAt > n2.updatedAt
            case .dateCreated:
                return n1.createdAt > n2.createdAt
            case .title:
                return n1.displayTitle.localizedCaseInsensitiveCompare(n2.displayTitle) == .orderedAscending
            }
        }
        
        return result
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header / Search Bar
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.wcagSecondaryText)
                        TextField("Search notes or #tags...", text: $searchText)
                            .onSubmit { openFirstMatch() }
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.wcagSecondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    Menu {
                        ForEach(NoteSortOption.allCases, id: \.self) { option in
                            Button(action: { sortOption = option }) {
                                HStack {
                                    Text(option.rawValue)
                                    if sortOption == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13))
                            .foregroundColor(.wcagSecondaryText)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .help("Sort by")
                    
                    Button(action: { createNewNoteInCurrentCategory() }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.wcagBlue)
                    }
                    .buttonStyle(.plain)
                    .help("New Note (⌘N)")
                    .keyboardShortcut("n", modifiers: [.command])
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            
            Divider()
            
            // Notes List
            if filteredNotes.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "note.text")
                        .font(.system(size: 36))
                        .foregroundColor(.wcagSecondaryText.opacity(0.6))
                    Text(searchText.isEmpty ? "No notes yet" : "No notes found")
                        .font(.headline)
                        .foregroundColor(.wcagSecondaryText)
                    if searchText.isEmpty {
                        Button("Create Note") {
                            createNewNoteInCurrentCategory()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Selection is drawn by the rows themselves (not by List) so the colors stay WCAG compliant
                // whatever the system accent color or focus state is
                ScrollViewReader { proxy in
                    List {
                        ForEach(filteredNotes) { note in
                            let isSelected = note.id == selectedNote?.id
                            NoteCardRow(note: note, showDestination: selectedCategory == .all, isSelected: isSelected)
                                .id(note.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedNote = note
                                    listFocused = true
                                }
                                .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                                .listRowSeparator(.hidden)
                                .contextMenu {
                                    noteContextMenu(for: note)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($listFocused)
                    .onKeyPress(.downArrow) { moveSelection(by: 1, proxy: proxy); return .handled }
                    .onKeyPress(.upArrow) { moveSelection(by: -1, proxy: proxy); return .handled }
                    .onKeyPress(.return) {
                        guard let note = selectedNote else { return .ignored }
                        EditorFocus.request(noteID: note.id, terms: NoteSearch.terms(in: searchText))
                        return .handled
                    }
                }
            }
        }
        .frame(minWidth: 260)
    }
    
    @ViewBuilder
    private func noteContextMenu(for note: Note) -> some View {
        Button(action: { storageManager.togglePin(note: note) }) {
            Label(note.isPinned ? "Unpin Note" : "Pin Note", systemImage: note.isPinned ? "pin.slash" : "pin")
        }
        
        Divider()
        
        Menu("Move to") {
            Button("Inbox") {
                storageManager.move(note: note, to: .inbox, targetName: nil)
            }
            
            if !storageManager.projects.isEmpty {
                Divider()
                Section("Projects") {
                    ForEach(storageManager.projects) { proj in
                        Button(proj.name) {
                            storageManager.move(note: note, to: .project, targetName: proj.name)
                        }
                    }
                }
            }
            
            if !storageManager.areas.isEmpty {
                Divider()
                Section("Areas") {
                    ForEach(storageManager.areas) { area in
                        Button(area.name) {
                            storageManager.move(note: note, to: .area, targetName: area.name)
                        }
                    }
                }
            }
        }
        
        if let path = note.filePath {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([path])
            }
        }
        
        Divider()
        
        Button(role: .destructive, action: {
            if selectedNote?.id == note.id {
                selectedNote = nil
            }
            storageManager.delete(note: note)
        }) {
            Label("Delete Note", systemImage: "trash")
        }
    }
    
    private func moveSelection(by step: Int, proxy: ScrollViewProxy) {
        let notes = filteredNotes
        guard !notes.isEmpty else { return }
        let current = notes.firstIndex { $0.id == selectedNote?.id } ?? (step > 0 ? -1 : notes.count)
        let next = notes[min(max(current + step, 0), notes.count - 1)]
        selectedNote = next
        proxy.scrollTo(next.id)
    }
    
    /// Return in the search box opens the selected note if it matches, otherwise the first match
    private func openFirstMatch() {
        let matches = filteredNotes
        guard let note = matches.first(where: { $0.id == selectedNote?.id }) ?? matches.first else { return }
        selectedNote = note
        EditorFocus.request(noteID: note.id, terms: NoteSearch.terms(in: searchText))
    }
    
    private func createNewNoteInCurrentCategory() {
        let (category, target): (CategoryType, String?) = {
            switch selectedCategory {
            case .all, .inbox, .dashboard:
                return (.inbox, nil)
            case .project(let name):
                return (.project, name)
            case .area(let name):
                return (.area, name)
            }
        }()
        
        let newNote = storageManager.createNote(
            title: "Untitled Note",
            content: "",
            category: category,
            targetName: target
        )
        selectedNote = newNote
    }
}

public struct NoteCardRow: View {
    let note: Note
    let showDestination: Bool
    /// A selected row sits on `wcagSelection`, so every color in it switches to white
    var isSelected: Bool = false
    
    private var onAccent: Bool { isSelected }
    private var secondaryColor: Color { isSelected ? .white : .wcagSecondaryText }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(onAccent ? .white : .wcagOrange)
                }
                
                Text(note.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(note.updatedAt.formatted(date: .numeric, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundColor(secondaryColor)
            }
            
            if !note.previewExcerpt.isEmpty {
                Text(note.previewExcerpt)
                    .font(.system(size: 12))
                    .foregroundColor(secondaryColor)
                    .lineLimit(2)
            }
            
            HStack(spacing: 6) {
                if showDestination || note.categoryType != .inbox {
                    HStack(spacing: 3) {
                        Image(systemName: destinationIcon)
                        Text(note.destinationDisplay)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(onAccent ? Color.black.opacity(0.22) : badgeColor.opacity(0.15))
                    .foregroundColor(onAccent ? .white : badgeColor)
                    .cornerRadius(4)
                }
                
                if let stats = note.checklistStats {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle")
                        Text("\(stats.completed)/\(stats.total)")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(onAccent ? .white : (stats.completed == stats.total ? .wcagGreen : .wcagSecondaryText))
                }
                
                Spacer()
                
                if let firstTag = note.tags.first {
                    Text("#\(firstTag)")
                        .font(.system(size: 10))
                        .foregroundColor(secondaryColor)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.wcagSelection : Color.clear)
        )
    }
    
    private var destinationIcon: String {
        switch note.categoryType {
        case .inbox: return "tray.fill"
        case .project:
            return NoteStorageManager.shared.projects.first(where: { $0.name == note.targetName })?.iconName ?? "folder.fill"
        case .area:
            return NoteStorageManager.shared.areas.first(where: { $0.name == note.targetName })?.iconName ?? "square.stack.3d.up.fill"
        }
    }
    
    private var badgeColor: Color {
        switch note.categoryType {
        case .inbox: return .wcagOrange
        case .project: return .wcagPurple
        case .area: return .wcagGreen
        }
    }
}
