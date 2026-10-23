import Foundation
import Combine
import SwiftUI

@MainActor
public final class NoteStorageManager: ObservableObject {
    public static let shared = NoteStorageManager()
    
    @Published public private(set) var notes: [Note] = []
    @Published public private(set) var projects: [ProjectArea] = []
    @Published public private(set) var areas: [ProjectArea] = []
    
    private let settings: AppSettings
    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var isPerformingInternalFileOperation: Bool = false
    private var cancellables = Set<AnyCancellable>()
    private let enableFileWatcher: Bool
    
    public init(settings: AppSettings = .shared, enableFileWatcher: Bool = true) {
        self.settings = settings
        self.enableFileWatcher = enableFileWatcher
        setupDirectories()
        loadAll()
        if enableFileWatcher {
            startWatching()
        }
        
        // Listen for directory changes in settings
        settings.$notesDirectoryURL
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.setupDirectories()
                self.loadAll()
                if self.enableFileWatcher {
                    self.startWatching()
                }
            }
            .store(in: &cancellables)
    }
    
    public func stopWatching() {
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
    }
    
    // MARK: - Directory Structure
    public var rootURL: URL {
        settings.notesDirectoryURL
    }
    
    public var inboxURL: URL {
        rootURL.appendingPathComponent("Inbox", isDirectory: true)
    }
    
    public var projectsURL: URL {
        rootURL.appendingPathComponent("Projects", isDirectory: true)
    }
    
    public var areasURL: URL {
        rootURL.appendingPathComponent("Areas", isDirectory: true)
    }
    
    public func setupDirectories() {
        let fileManager = FileManager.default
        let dirs = [inboxURL, projectsURL, areasURL]
        for dir in dirs {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            }
        }
    }
    
    // MARK: - Loading & Discovery
    public func loadAll() {
        setupDirectories()
        let fileManager = FileManager.default
        
        // 1. Discover Projects
        var discoveredProjects: [ProjectArea] = []
        if let projectDirs = try? fileManager.contentsOfDirectory(at: projectsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for dir in projectDirs {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                    var customIcon: String? = nil
                    if let data = try? Data(contentsOf: dir.appendingPathComponent(".metadata.json")),
                       let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                        customIcon = dict["icon"]
                    }
                    discoveredProjects.append(ProjectArea(name: dir.lastPathComponent, type: .project, customIcon: customIcon))
                }
            }
        }
        self.projects = discoveredProjects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        // 2. Discover Areas
        var discoveredAreas: [ProjectArea] = []
        if let areaDirs = try? fileManager.contentsOfDirectory(at: areasURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for dir in areaDirs {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                    var customIcon: String? = nil
                    if let data = try? Data(contentsOf: dir.appendingPathComponent(".metadata.json")),
                       let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                        customIcon = dict["icon"]
                    }
                    discoveredAreas.append(ProjectArea(name: dir.lastPathComponent, type: .area, customIcon: customIcon))
                }
            }
        }
        self.areas = discoveredAreas.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        // 3. Discover Notes
        var loadedNotes: [Note] = []
        
        // Load Inbox notes
        loadedNotes.append(contentsOf: loadNotesInDirectory(inboxURL, defaultCategory: .inbox, targetName: nil))
        
        // Load Project notes
        for project in self.projects {
            let pDir = projectsURL.appendingPathComponent(project.name, isDirectory: true)
            loadedNotes.append(contentsOf: loadNotesInDirectory(pDir, defaultCategory: .project, targetName: project.name))
        }
        
        // Load Area notes
        for area in self.areas {
            let aDir = areasURL.appendingPathComponent(area.name, isDirectory: true)
            loadedNotes.append(contentsOf: loadNotesInDirectory(aDir, defaultCategory: .area, targetName: area.name))
        }
        
        // Sort notes: pinned first, then newest updated
        self.notes = loadedNotes.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.updatedAt > $1.updatedAt
        }
    }
    
    private func loadNotesInDirectory(_ directory: URL, defaultCategory: CategoryType, targetName: String?) -> [Note] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        
        var result: [Note] = []
        for file in files where file.pathExtension.lowercased() == "md" {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                var note = Note.parse(from: content, fileURL: file)
                // If frontmatter didn't specify category/target, infer from directory location
                if note.categoryType == .inbox && defaultCategory != .inbox {
                    note.categoryType = defaultCategory
                    note.targetName = targetName
                }
                result.append(note)
            }
        }
        return result
    }
    
    // MARK: - CRUD Operations
    @discardableResult
    public func createNote(
        title: String = "",
        content: String = "",
        category: CategoryType = .inbox,
        targetName: String? = nil,
        tags: [String] = []
    ) -> Note {
        var note = Note(
            title: title,
            content: content,
            categoryType: category,
            targetName: targetName,
            createdAt: Date(),
            updatedAt: Date(),
            tags: tags
        )
        
        let destinationDir = targetDirectory(for: category, targetName: targetName)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: destinationDir.path) {
            try? fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }
        
        let fileName = generateUniqueFileName(for: note, in: destinationDir)
        let fileURL = destinationDir.appendingPathComponent(fileName)
        note.filePath = fileURL
        
        save(note: note)
        return note
    }
    
    public func save(note: Note) {
        var updatedNote = note
        updatedNote.updatedAt = Date()
        
        let fileManager = FileManager.default
        let destinationDir = targetDirectory(for: updatedNote.categoryType, targetName: updatedNote.targetName)
        if !fileManager.fileExists(atPath: destinationDir.path) {
            try? fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }
        
        // Determine file URL
        let fileURL: URL
        if let existing = updatedNote.filePath, existing.deletingLastPathComponent().path == destinationDir.path {
            fileURL = existing
        } else {
            // If moved to different directory or no file path yet
            if let oldURL = updatedNote.filePath, fileManager.fileExists(atPath: oldURL.path) {
                try? fileManager.removeItem(at: oldURL)
            }
            let fileName = generateUniqueFileName(for: updatedNote, in: destinationDir)
            fileURL = destinationDir.appendingPathComponent(fileName)
            updatedNote.filePath = fileURL
        }
        
        isPerformingInternalFileOperation = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isPerformingInternalFileOperation = false
            }
        }
        
        let markdown = updatedNote.serializeToMarkdown()
        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Update in-memory state
            if let idx = notes.firstIndex(where: { $0.id == updatedNote.id }) {
                notes[idx] = updatedNote
            } else {
                notes.insert(updatedNote, at: 0)
            }
            sortNotes()
        } catch {
            print("Failed to save note \(updatedNote.id): \(error)")
        }
    }
    
    public func delete(note: Note) {
        isPerformingInternalFileOperation = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isPerformingInternalFileOperation = false
            }
        }
        
        if let fileURL = note.filePath {
            try? FileManager.default.removeItem(at: fileURL)
        }
        notes.removeAll { $0.id == note.id }
    }
    
    public func move(note: Note, to category: CategoryType, targetName: String?) {
        var updatedNote = note
        updatedNote.categoryType = category
        updatedNote.targetName = targetName
        save(note: updatedNote)
    }
    
    public func togglePin(note: Note) {
        var updated = note
        updated.isPinned.toggle()
        save(note: updated)
    }
    
    // MARK: - Project / Area Management
    public func createProject(name: String, icon: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dir = projectsURL.appendingPathComponent(trimmed, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let icon = icon, !icon.isEmpty {
            let meta = ["icon": icon]
            if let data = try? JSONEncoder().encode(meta) {
                try? data.write(to: dir.appendingPathComponent(".metadata.json"))
            }
        }
        loadAll()
    }
    
    public func deleteProject(name: String) {
        let dir = projectsURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        loadAll()
    }
    
    public func createArea(name: String, icon: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dir = areasURL.appendingPathComponent(trimmed, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let icon = icon, !icon.isEmpty {
            let meta = ["icon": icon]
            if let data = try? JSONEncoder().encode(meta) {
                try? data.write(to: dir.appendingPathComponent(".metadata.json"))
            }
        }
        loadAll()
    }
    
    public func deleteArea(name: String) {
        let dir = areasURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        loadAll()
    }
    
    // MARK: - Helpers
    private func targetDirectory(for category: CategoryType, targetName: String?) -> URL {
        switch category {
        case .inbox:
            return inboxURL
        case .project:
            let name = targetName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name = name, !name.isEmpty {
                return projectsURL.appendingPathComponent(name, isDirectory: true)
            }
            return projectsURL.appendingPathComponent("General", isDirectory: true)
        case .area:
            let name = targetName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name = name, !name.isEmpty {
                return areasURL.appendingPathComponent(name, isDirectory: true)
            }
            return areasURL.appendingPathComponent("General", isDirectory: true)
        }
    }
    
    private func generateUniqueFileName(for note: Note, in directory: URL) -> String {
        let rawTitle = note.displayTitle
        let sanitized = sanitizeFileName(rawTitle)
        let baseName = sanitized.isEmpty ? "note" : sanitized
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let datePrefix = dateFormatter.string(from: note.createdAt)
        
        let candidate = "\(datePrefix)_\(baseName).md"
        let target = directory.appendingPathComponent(candidate)
        if !FileManager.default.fileExists(atPath: target.path) || target.path == note.filePath?.path {
            return candidate
        }
        
        // Otherwise append UUID short slice
        let shortId = note.id.uuidString.prefix(6)
        return "\(datePrefix)_\(baseName)_\(shortId).md"
    }
    
    private func sanitizeFileName(_ string: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>| \n\t\r")
        let parts = string.components(separatedBy: invalid).filter { !$0.isEmpty }
        let joined = parts.joined(separator: "-")
        return String(joined.prefix(40))
    }
    
    private func sortNotes() {
        notes.sort {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.updatedAt > $1.updatedAt
        }
    }
    
    // MARK: - File System Monitoring
    private func startWatching() {
        fileWatcherSource?.cancel()
        
        let descriptor = open(rootURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link],
            queue: DispatchQueue.global(qos: .utility)
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard !self.isPerformingInternalFileOperation else { return }
                self.loadAll()
            }
        }
        
        source.setCancelHandler {
            close(descriptor)
        }
        
        source.resume()
        self.fileWatcherSource = source
    }
}
