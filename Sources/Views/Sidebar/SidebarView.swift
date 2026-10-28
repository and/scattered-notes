import SwiftUI

public enum SidebarSelection: Hashable {
    case dashboard
    case all
    case inbox
    case project(name: String)
    case area(name: String)
    
    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .all: return "All Notes"
        case .inbox: return "Inbox"
        case .project(let name): return name
        case .area(let name): return name
        }
    }

    /// Projects and areas have their own dashboard, shown until a note is opened
    public var hasOwnDashboard: Bool {
        switch self {
        case .project, .area: return true
        default: return false
        }
    }

    /// Whether `note` is listed under this selection
    public func contains(_ note: Note) -> Bool {
        switch self {
        case .all, .dashboard: return true
        case .inbox: return note.categoryType == .inbox
        case .project(let name): return note.categoryType == .project && note.targetName == name
        case .area(let name): return note.categoryType == .area && note.targetName == name
        }
    }
}

public struct SidebarView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    @ObservedObject var settings = AppSettings.shared
    
    @Binding var selection: SidebarSelection
    @State private var showingNewProjectDialog: Bool = false
    @State private var showingNewAreaDialog: Bool = false
    @State private var itemToDelete: ProjectArea? = nil
    @State private var showingDeleteAlert: Bool = false
    
    public init(selection: Binding<SidebarSelection>) {
        self._selection = selection
    }
    
    public var body: some View {
        List(selection: $selection) {
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
                    .badge(storageManager.notes.filter { $0.categoryType == .inbox }.count)
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
                        .badge(storageManager.notes.filter { $0.categoryType == .project && $0.targetName == project.name }.count)
                    }
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
            
            Section {
                ForEach(storageManager.areas) { area in
                    NavigationLink(value: SidebarSelection.area(name: area.name)) {
                        Label {
                            Text(area.name)
                        } icon: {
                            Image(systemName: area.iconName)
                                .prominenceAwareColor(.wcagGreen)
                        }
                        .badge(storageManager.notes.filter { $0.categoryType == .area && $0.targetName == area.name }.count)
                    }
                    .contextMenu {
                        Button("Reveal in Finder") {
                            let url = storageManager.areasURL.appendingPathComponent(area.name)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        Divider()
                        Button(role: .destructive, action: {
                            itemToDelete = area
                            showingDeleteAlert = true
                        }) {
                            Label("Delete Area", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Areas")
                    Spacer()
                    Button(action: { showingNewAreaDialog = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.wcagSecondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Add New Area")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Menu {
                        Text(storageManager.rootURL.path)
                        Divider()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.open(storageManager.rootURL)
                        }
                        Button("Change Notes Folder…") {
                            StorageFolderPicker.chooseAndRelocate(storageManager: storageManager)
                        }
                    } label: {
                        Label("Notes Folder", systemImage: "folder")
                            .font(.caption)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundColor(.wcagSecondaryText)
                    .help(storageManager.rootURL.path)
                    
                    Spacer()
                    
                    Button(action: {
                        QuickCapturePanel.shared.showPanel()
                    }) {
                        HStack(spacing: 3) {
                            Text(settings.quickCaptureShortcut.displayString)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.wcagBadgeBackground)
                                .cornerRadius(3)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.wcagBorder, lineWidth: 1))
                            Text("Quick Note")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.wcagSecondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
            }
        }
        .sheet(isPresented: $showingNewProjectDialog) {
            NewProjectAreaSheet(type: .project) { name, icon in
                storageManager.createProject(name: name, icon: icon)
                selection = .project(name: name)
            }
        }
        .sheet(isPresented: $showingNewAreaDialog) {
            NewProjectAreaSheet(type: .area) { name, icon in
                storageManager.createArea(name: name, icon: icon)
                selection = .area(name: name)
            }
        }
        .alert("Delete \(itemToDelete?.type == .project ? "Project" : "Area")?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    if item.type == .project {
                        storageManager.deleteProject(name: item.name)
                        if selection == .project(name: item.name) {
                            selection = .inbox
                        }
                    } else {
                        storageManager.deleteArea(name: item.name)
                        if selection == .area(name: item.name) {
                            selection = .inbox
                        }
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
