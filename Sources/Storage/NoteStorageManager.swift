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
    private var agendaLog = AgendaLog()
    
    public init(settings: AppSettings = .shared, enableFileWatcher: Bool = true) {
        self.settings = settings
        self.enableFileWatcher = enableFileWatcher
        setupDirectories()
        loadAll()
        if enableFileWatcher {
            startWatching()
        }
        
        // Listen for directory changes in settings
        // @Published emits on willSet, so hop to the next main-queue turn to read the new value
        settings.$notesDirectoryURL
            .dropFirst()
            .receive(on: DispatchQueue.main)
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
    
    /// Records when each actionable or dated line first appeared; see `AgendaLog`.
    public var agendaLogURL: URL {
        rootURL.appendingPathComponent(AgendaLog.fileName)
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
        
        // A crash while moving a note can leave its file in two folders. Show the newest copy and
        // leave the other file on disk untouched
        var newestByID: [UUID: Note] = [:]
        for note in loadedNotes where (newestByID[note.id]?.updatedAt ?? .distantPast) <= note.updatedAt {
            newestByID[note.id] = note
        }
        loadedNotes = loadedNotes.filter { newestByID[$0.id]?.filePath == $0.filePath }
        
        // Pick up lines written outside the app, anchoring them to when the file last changed
        loadAgendaLog()
        var logChanged = false
        for note in loadedNotes {
            let fallback = agendaLog.notes[note.id.uuidString] == nil ? note.createdAt : note.updatedAt
            logChanged = recordAgenda(for: note, seenAt: fallback) || logChanged
        }
        let liveIDs = Set(loadedNotes.map { $0.id.uuidString })
        for id in agendaLog.notes.keys where !liveIDs.contains(id) {
            agendaLog.notes[id] = nil
            logChanged = true
        }
        if logChanged { writeAgendaLog() }
        
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
        // If note already exists, verify something actually changed before updating timestamp and re-sorting
        if let existing = notes.first(where: { $0.id == note.id }) {
            if existing.title == note.title &&
               existing.content == note.content &&
               existing.categoryType == note.categoryType &&
               existing.targetName == note.targetName &&
               existing.tags == note.tags &&
               existing.isPinned == note.isPinned {
                return
            }
        }
        
        var updatedNote = note
        updatedNote.updatedAt = Date()
        
        let fileManager = FileManager.default
        let destinationDir = targetDirectory(for: updatedNote.categoryType, targetName: updatedNote.targetName)
        if !fileManager.fileExists(atPath: destinationDir.path) {
            try? fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }
        
        // Determine file URL
        let fileURL: URL
        var staleURL: URL?
        if let existing = updatedNote.filePath, existing.deletingLastPathComponent().path == destinationDir.path {
            fileURL = existing
        } else {
            // Moved to a different directory or no file path yet. The old file goes only after the
            // new one is safely on disk, so a crash in between leaves a duplicate, never a lost note
            if let oldURL = updatedNote.filePath, fileManager.fileExists(atPath: oldURL.path) {
                staleURL = oldURL
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
            if let staleURL, staleURL.path != fileURL.path {
                try? fileManager.removeItem(at: staleURL)
            }
            
            // Update in-memory state
            if let idx = notes.firstIndex(where: { $0.id == updatedNote.id }) {
                notes[idx] = updatedNote
            } else {
                notes.insert(updatedNote, at: 0)
            }
            sortNotes()
            if recordAgenda(for: updatedNote, seenAt: Date()) { writeAgendaLog() }
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
        if agendaLog.notes.removeValue(forKey: note.id.uuidString) != nil { writeAgendaLog() }
    }
    
    public func move(note: Note, to category: CategoryType, targetName: String?) {
        var updatedNote = note
        updatedNote.categoryType = category
        updatedNote.targetName = targetName
        save(note: updatedNote)
    }
    
    public func toggleChecklistItem(noteID: UUID, lineIndex: Int) {
        guard var note = notes.first(where: { $0.id == noteID }) else { return }
        note.content = Note.togglingChecklistLine(lineIndex, in: note.content)
        save(note: note)
    }
    
    /// Checklist items and dated lines from every note, for the dashboard.
    public var agendaItems: [AgendaItem] {
        notes.flatMap { agendaItems(for: $0) }
    }
    
    /// Checklist items and dated lines of one note, dated from when each line was first written.
    public func agendaItems(for note: Note) -> [AgendaItem] {
        AgendaExtractor.items(from: note, anchors: agendaLog.anchors(for: note.id))
    }
    
    // MARK: - Agenda Log
    private func loadAgendaLog() {
        guard let data = try? Data(contentsOf: agendaLogURL),
              let log = try? AgendaLog.decoder.decode(AgendaLog.self, from: data) else {
            agendaLog = AgendaLog()
            return
        }
        agendaLog = log
    }
    
    private func writeAgendaLog() {
        isPerformingInternalFileOperation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isPerformingInternalFileOperation = false
        }
        guard let data = try? AgendaLog.encoder.encode(agendaLog) else { return }
        try? data.write(to: agendaLogURL, options: .atomic)
    }
    
    /// Adds log entries for new lines and drops entries for lines that are gone. Returns whether anything changed.
    @discardableResult
    private func recordAgenda(for note: Note, seenAt: Date) -> Bool {
        let lines = AgendaExtractor.items(from: note).map { (key: AgendaExtractor.logKey(for: $0.text), line: $0.text) }
        return agendaLog.update(noteID: note.id, lines: lines, seenAt: seenAt)
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
    
    // MARK: - Storage Folder Relocation
    public enum RelocationError: LocalizedError {
        case nestedFolder

        public var errorDescription: String? {
            switch self {
            case .nestedFolder:
                return "The new folder can't be inside a folder that currently holds your notes."
            }
        }
    }

    /// Points the app at `newRoot` and moves every note (plus project/area folders and their
    /// metadata) from the current folder and the default folder into it.
    /// Returns the number of note files moved.
    @discardableResult
    public func relocateStorage(
        to newRoot: URL,
        defaultRoot: URL = AppSettings.defaultNotesDirectoryURL
    ) throws -> Int {
        let destination = newRoot.standardizedFileURL
        var sources = [rootURL.standardizedFileURL]
        if !sources.contains(defaultRoot.standardizedFileURL) {
            sources.append(defaultRoot.standardizedFileURL)
        }
        sources.removeAll { $0.path == destination.path }

        for source in sources where Self.isInside(destination, source) {
            throw RelocationError.nestedFolder
        }

        stopWatching()
        isPerformingInternalFileOperation = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isPerformingInternalFileOperation = false
            }
        }

        var movedCount = 0
        for source in sources {
            for folder in ["Inbox", "Projects", "Areas"] {
                movedCount += try moveContents(
                    of: source.appendingPathComponent(folder, isDirectory: true),
                    into: destination.appendingPathComponent(folder, isDirectory: true)
                )
            }
        }

        if settings.notesDirectoryURL.standardizedFileURL.path != destination.path {
            settings.notesDirectoryURL = destination
        }
        // Reload now rather than waiting for the async settings sink
        loadAll()
        if enableFileWatcher {
            startWatching()
        }
        return movedCount
    }

    private static func isInside(_ child: URL, _ parent: URL) -> Bool {
        let parentPath = parent.path.hasSuffix("/") ? parent.path : parent.path + "/"
        return child.path.hasPrefix(parentPath)
    }

    /// Recursively moves `.md` notes and `.metadata.json` files, keeping the folder layout.
    /// Name clashes on notes get a numeric suffix; existing metadata in the destination wins.
    private func moveContents(of sourceDir: URL, into destDir: URL) throws -> Int {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return 0
        }
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)

        var movedCount = 0
        for item in items {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            let name = item.lastPathComponent

            if isDir.boolValue {
                movedCount += try moveContents(of: item, into: destDir.appendingPathComponent(name, isDirectory: true))
            } else if name == ".metadata.json" {
                let target = destDir.appendingPathComponent(name)
                if !fileManager.fileExists(atPath: target.path) {
                    try fileManager.moveItem(at: item, to: target)
                }
            } else if item.pathExtension.lowercased() == "md" {
                try fileManager.moveItem(at: item, to: uniqueDestination(for: name, in: destDir))
                movedCount += 1
            }
        }

        // Clean up the source folder if nothing but Finder clutter is left
        let leftovers = (try? fileManager.contentsOfDirectory(atPath: sourceDir.path)) ?? []
        if leftovers.allSatisfy({ $0 == ".DS_Store" }) {
            try? fileManager.removeItem(at: sourceDir)
        }
        return movedCount
    }

    private func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let candidate = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var index = 2
        while true {
            let next = directory.appendingPathComponent("\(base)_\(index).\(ext)")
            if !FileManager.default.fileExists(atPath: next.path) { return next }
            index += 1
        }
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
        
        // Handlers inherit @MainActor isolation from this class, so they must run on the main
        // queue; Swift 6 traps at runtime if they fire on a background queue
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            guard let self = self, !self.isPerformingInternalFileOperation else { return }
            self.loadAll()
        }
        
        source.setCancelHandler {
            close(descriptor)
        }
        
        source.resume()
        self.fileWatcherSource = source
    }
}
