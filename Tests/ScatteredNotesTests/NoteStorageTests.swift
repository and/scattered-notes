import XCTest
@testable import ScatteredNotes

final class NoteStorageTests: XCTestCase {
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }
    
    func testNoteSerializationAndParsing() {
        let originalNote = Note(
            id: UUID(),
            title: "Test Note Title",
            content: "This is test content.\n- [ ] Task 1\n- [x] Task 2",
            categoryType: .project,
            targetName: "ScatteredApp",
            createdAt: Date(),
            updatedAt: Date(),
            tags: ["swift", "test"],
            isPinned: true
        )
        
        let markdown = originalNote.serializeToMarkdown()
        XCTAssertTrue(markdown.contains("title: \"Test Note Title\""))
        XCTAssertTrue(markdown.contains("type: project"))
        XCTAssertTrue(markdown.contains("target: \"ScatteredApp\""))
        XCTAssertTrue(markdown.contains("pinned: true"))
        XCTAssertTrue(markdown.contains("tags: [\"swift\", \"test\"]"))
        XCTAssertTrue(markdown.contains("- [ ] Task 1"))
        
        let parsedNote = Note.parse(from: markdown)
        XCTAssertEqual(parsedNote.id, originalNote.id)
        XCTAssertEqual(parsedNote.title, "Test Note Title")
        XCTAssertEqual(parsedNote.categoryType, .project)
        XCTAssertEqual(parsedNote.targetName, "ScatteredApp")
        XCTAssertEqual(parsedNote.isPinned, true)
        XCTAssertEqual(parsedNote.tags, ["swift", "test"])
        XCTAssertTrue(parsedNote.content.contains("- [ ] Task 1"))
    }
    
    func testChecklistStats() {
        let note = Note(
            title: "Task list",
            content: "My tasks:\n- [ ] Todo item\n- [x] Done item\n* [ ] Another todo\n* [x] Another done"
        )
        
        let stats = note.checklistStats
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.completed, 2)
        XCTAssertEqual(stats?.total, 4)
    }
    
    func testFallbackDisplayTitle() {
        let noteWithoutTitle = Note(
            title: "",
            content: "# Meeting with Team\nDiscuss roadmap items"
        )
        XCTAssertEqual(noteWithoutTitle.displayTitle, "Meeting with Team")
        
        let noteWithoutHeader = Note(
            title: "",
            content: "Quick thought on architecture"
        )
        XCTAssertEqual(noteWithoutHeader.displayTitle, "Quick thought on architecture")
    }
    
    @MainActor
    func testProjectAndAreaDirectoryScaffolding() {
        let settings = AppSettings(notesDirectoryURL: tempDirectory)
        let manager = NoteStorageManager(settings: settings, enableFileWatcher: false)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.inboxURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.projectsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.areasURL.path))
        
        // Create project
        manager.createProject(name: "New Project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.projectsURL.appendingPathComponent("New Project").path))
        XCTAssertEqual(manager.projects.count, 1)
        XCTAssertEqual(manager.projects.first?.name, "New Project")
        
        // Create note in project
        let note = manager.createNote(
            title: "Roadmap",
            content: "Sprint 1 deliverables",
            category: .project,
            targetName: "New Project"
        )
        
        XCTAssertEqual(manager.notes.count, 1)
        XCTAssertNotNil(note.filePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.filePath!.path))
        
        // Move note to Inbox
        manager.move(note: note, to: .inbox, targetName: nil)
        XCTAssertEqual(manager.notes.first?.categoryType, .inbox)
        XCTAssertEqual(manager.notes.first?.filePath?.deletingLastPathComponent().path, manager.inboxURL.path)
        
        // Test custom icon
        manager.createProject(name: "App Project", icon: "rocket.fill")
        let appProject = manager.projects.first(where: { $0.name == "App Project" })
        XCTAssertNotNil(appProject)
        XCTAssertEqual(appProject?.iconName, "rocket.fill")
    }
}
