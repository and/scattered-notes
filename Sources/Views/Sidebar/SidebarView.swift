import SwiftUI

public enum SidebarSelection: Hashable {
    case dashboard
    case all
    case inbox
    case project(name: String)
    case person(name: String)
    case tag(name: String)
    /// A note picked from the Recent list: shown among all notes, with that note open
    case note(id: UUID)
    
    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .all, .note: return "All Notes"
        case .inbox: return "Inbox"
        case .project(let name): return name
        case .person(let name): return "@" + name
        case .tag(let name): return "#" + name
        }
    }

    /// Projects, people and tags have their own dashboard, shown until a note is opened
    public var hasOwnDashboard: Bool {
        switch self {
        case .project, .person, .tag: return true
        default: return false
        }
    }

    /// Whether the detail pane shows a dashboard until a note is opened: the Dashboard itself, or the
    /// dashboard of a project, person or tag
    public var opensOnDashboard: Bool { self == .dashboard || hasOwnDashboard }

    /// The place whose notes the list shows: a note picked from Recent is listed among all notes
    public var listScope: SidebarSelection {
        if case .note = self { return .all }
        return self
    }

    /// Whether `note` is listed under this selection
    public func contains(_ note: Note) -> Bool {
        switch self {
        case .all, .dashboard, .note: return true
        case .inbox: return note.categoryType == .inbox
        case .project(let name): return note.categoryType == .project && note.targetName == name
        case .person(let name): return note.people.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        case .tag(let name): return note.tags.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
    }
}

/// A pane the keyboard can move to, so the arrow keys walk between the project list, the notes and back
public enum MainPane: Hashable {
    case sidebar, list, dashboard
}

public struct SidebarView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    @ObservedObject var settings = AppSettings.shared
    
    @Binding var selection: SidebarSelection
    /// Set to `.sidebar` to move keyboard focus here; cleared once it has
    @Binding var focusRequest: MainPane?
    /// Right arrow: carry on into the notes of the selected project
    var onMoveRight: () -> Void = {}
    /// Reports whether the project list has the keyboard, so the notes can draw their selection to match
    @Binding var hasFocus: Bool
    /// Called when a note is dropped on a project or the Inbox; says whether it moved
    var onDropNote: (UUID, SidebarSelection) -> Bool = { _, _ in false }
    @State private var dropHighlight: SidebarSelection?
    @FocusState private var sidebarFocused: Bool
    @State private var showingNewProjectDialog: Bool = false
    @State private var itemToDelete: ProjectArea? = nil
    @State private var showingDeleteAlert: Bool = false
    
    public init(selection: Binding<SidebarSelection>, focusRequest: Binding<MainPane?> = .constant(nil), hasFocus: Binding<Bool> = .constant(false), onMoveRight: @escaping () -> Void = {},
                onDropNote: @escaping (UUID, SidebarSelection) -> Bool = { _, _ in false }) {
        self._selection = selection
        self._focusRequest = focusRequest
        self._hasFocus = hasFocus
        self.onMoveRight = onMoveRight
        self.onDropNote = onDropNote
    }

    /// Each name used for one kind of mark across all notes, with how many notes use it, sorted by
    /// name. Names that differ only in case count as one, spelled as first seen.
    private func counted(_ names: (Note) -> [String]) -> [(name: String, count: Int)] {
        var spelling: [String: String] = [:]
        var counts: [String: Int] = [:]
        for note in storageManager.notes {
            let found = names(note)
            for name in Set(found.map { $0.lowercased() }) {
                counts[name, default: 0] += 1
            }
            for name in found where spelling[name.lowercased()] == nil {
                spelling[name.lowercased()] = name
            }
        }
        return counts.map { (name: spelling[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// Notes in the Inbox and in each project, counted in one pass over the notes
    private func rowCounts() -> (inbox: Int, projects: [String: Int]) {
        var inbox = 0
        var projects: [String: Int] = [:]
        for note in storageManager.notes {
            if note.categoryType == .inbox {
                inbox += 1
            } else if note.categoryType == .project, let name = note.targetName {
                projects[name, default: 0] += 1
            }
        }
        return (inbox, projects)
    }
    
    public var body: some View {
        let counts = rowCounts()
        return List(selection: $selection) {
            Section("Quick Access") {
                NavigationLink(value: SidebarSelection.dashboard) {
                    Label {
                        Text("Dashboard")
                    } icon: {
                        Image(systemName: "square.grid.2x2.fill")
                            .prominenceAwareColor(.wcagPurple)
                    }
                }
                
                NavigationLink(value: SidebarSelection.all) {
                    Label {
                        Text("All Notes")
                    } icon: {
                        Image(systemName: "tray.2.fill")
                            .prominenceAwareColor(.wcagBlue)
                    }
                    .badge(storageManager.notes.count)
                }
                
                NavigationLink(value: SidebarSelection.inbox) {
                    Label {
                        Text("Inbox")
                    } icon: {
                        Image(systemName: "tray.fill")
                            .prominenceAwareColor(.wcagOrange)
                    }
                    .badge(counts.inbox)
                }
                .modifier(NoteDropTarget(selection: .inbox, highlighted: $dropHighlight, onDrop: onDropNote))
            }
            
            let recents = RecentNotes.latest(storageManager.notes, hidden: settings.hiddenRecents)
            if !recents.isEmpty {
                Section("Recent") {
                    ForEach(recents) { note in
                        RecentNoteRow(note: note,
                                      onRemove: { settings.hiddenRecents[note.id] = note.updatedAt })
                    }
                }
            }

            Section {
                ForEach(storageManager.projects) { project in
                    NavigationLink(value: SidebarSelection.project(name: project.name)) {
                        Label {
                            Text(project.name)
                        } icon: {
                            Image(systemName: project.iconName)
                                .prominenceAwareColor(.wcagPurple)
                        }
                        .badge(counts.projects[project.name, default: 0])
                    }
                    .modifier(NoteDropTarget(selection: .project(name: project.name), highlighted: $dropHighlight, onDrop: onDropNote))
                    .contextMenu {
                        Button("Reveal in Finder") {
                            let url = storageManager.projectsURL.appendingPathComponent(project.name)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        Divider()
                        Button(role: .destructive, action: {
                            itemToDelete = project
                            showingDeleteAlert = true
                        }) {
                            Label("Delete Project", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Button(action: { showingNewProjectDialog = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.wcagSecondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Add New Project")
                }
            }
            
            let people = counted { storageManager.people(in: $0) }
            if !people.isEmpty {
                Section("People") {
                    ForEach(people, id: \.name) { person in
                        NavigationLink(value: SidebarSelection.person(name: person.name)) {
                            Label {
                                Text(person.name)
                            } icon: {
                                Image(systemName: "person.fill")
                                    .prominenceAwareColor(.wcagBlue)
                            }
                            .badge(person.count)
                        }
                    }
                }
            }

            let tags = counted(\.tags)
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags, id: \.name) { tag in
                        NavigationLink(value: SidebarSelection.tag(name: tag.name)) {
                            Label {
                                Text(tag.name)
                            } icon: {
                                Image(systemName: "number")
                                    .prominenceAwareColor(.wcagGreen)
                            }
                            .badge(tag.count)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .focused($sidebarFocused)
        .onKeyPress(.rightArrow) { onMoveRight(); return .handled }
        .onChange(of: sidebarFocused) { _, focused in hasFocus = focused }
        .onChange(of: focusRequest) { _, request in
            guard request == .sidebar else { return }
            sidebarFocused = true
            focusRequest = nil
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.wcagSecondaryText)
                .help("Settings")
                .accessibilityLabel("Settings")
                Spacer()
                Text("v\(AppVersion.current.description)")
                    .font(.caption)
                    .foregroundColor(.wcagSecondaryText)
                    .help("Scattered Notes \(AppVersion.current.description)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // A bar of its own, so the folders and notes scroll under it instead of showing through the gear and version
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .sheet(isPresented: $showingNewProjectDialog) {
            NewProjectAreaSheet(type: .project) { name, icon in
                storageManager.createProject(name: name, icon: icon)
                selection = .project(name: name)
            }
        }
        .alert("Delete Project?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    storageManager.deleteProject(name: item.name)
                    if selection == .project(name: item.name) {
                        selection = .inbox
                    }
                }
            }
        } message: {
            if let item = itemToDelete {
                Text("Are you sure you want to delete \"\(item.name)\"? This will remove its directory.")
            }
        }
    }
}

/// A note under Recent: a row of the project list, so the arrow keys reach it, with an x on hover (and a menu
/// item) to take it off the list. Clicking it also puts the cursor in the note.
private struct RecentNoteRow: View {
    let note: Note
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: SidebarSelection.note(id: note.id)) {
            HStack(spacing: 4) {
                Label {
                    Text(note.displayTitle).lineLimit(1)
                } icon: {
                    Image(systemName: note.categoryType.iconName)
                        .foregroundColor(.wcagSecondaryText)
                }
                Spacer(minLength: 0)
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.wcagSecondaryText)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .help("Remove from Recent")
                .accessibilityLabel("Remove \(note.displayTitle) from Recent")
            }
            .contentShape(Rectangle())
        }
        .simultaneousGesture(TapGesture().onEnded { EditorFocus.request(noteID: note.id) })
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Remove from Recent", action: onRemove)
        }
    }
}
