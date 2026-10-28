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
    func testProjectDirectoryScaffolding() {
        let settings = AppSettings(notesDirectoryURL: tempDirectory, defaults: UserDefaults(suiteName: "com.scatterednotes.app.tests.storage")!)
        let manager = NoteStorageManager(settings: settings, enableFileWatcher: false)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.inboxURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.projectsURL.path))
        // Areas were replaced by tags, so no Areas folder is made
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.areasURL.path))
        
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
    
    func testRemoveProjectTagFromContent() {
        // Tag at end of sentence
        XCTAssertEqual(
            Note.removeProjectTag(from: "Buy groceries +groceries", targetName: "groceries"),
            "Buy groceries"
        )
        // Tag with punctuation at end
        XCTAssertEqual(
            Note.removeProjectTag(from: "Buy groceries +groceries.", targetName: "groceries"),
            "Buy groceries."
        )
        // Tag at start
        XCTAssertEqual(
            Note.removeProjectTag(from: "+groceries Buy groceries", targetName: "groceries"),
            "Buy groceries"
        )
        // Tag in middle
        XCTAssertEqual(
            Note.removeProjectTag(from: "Buy +groceries for dinner", targetName: "groceries"),
            "Buy for dinner"
        )
        // Tag with colon
        XCTAssertEqual(
            Note.removeProjectTag(from: "+groceries: buy milk, eggs", targetName: "groceries"),
            "buy milk, eggs"
        )
        // Checklist task with tag
        XCTAssertEqual(
            Note.removeProjectTag(from: "- [ ] Call dentist +health", targetName: "health"),
            "- [ ] Call dentist"
        )
        // Email address preserved (not stripped)
        XCTAssertEqual(
            Note.removeProjectTag(from: "Contact user@groceries.com for info", targetName: "groceries"),
            "Contact user@groceries.com for info"
        )
        // Project name with spaces
        XCTAssertEqual(
            Note.removeProjectTag(from: "Review PR +MobileApp", targetName: "Mobile App"),
            "Review PR"
        )
        // Plus prefix tag
        XCTAssertEqual(
            Note.removeProjectTag(from: "Fix crash +MobileApp #bug", targetName: "MobileApp"),
            "Fix crash #bug"
        )
        // @ marks a person, never a project
        XCTAssertEqual(
            Note.removeProjectTag(from: "Ask @groceries about it", targetName: "groceries"),
            "Ask @groceries about it"
        )
        // Wiki link
        XCTAssertEqual(
            Note.removeProjectTag(from: "Daily jog [[Health]]", targetName: "Health"),
            "Daily jog"
        )
    }

    @MainActor
    func testRecognisesTheAppsICloudFolder() {
        let mac = URL(fileURLWithPath: "/Users/me/Library/Mobile Documents/iCloud~com~scatterednotes/Documents")
        let phone = URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/iCloud~com~scatterednotes/Documents/Inbox")
        XCTAssertTrue(ICloudFolder.contains(mac))
        XCTAssertTrue(ICloudFolder.contains(phone))
        XCTAssertFalse(ICloudFolder.contains(URL(fileURLWithPath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/ScatteredNotes")))
        XCTAssertFalse(ICloudFolder.contains(AppSettings.defaultNotesDirectoryURL))
    }

    @MainActor
    func testOnlyAChosenNotesFolderCountsAsChosen() {
        let suite = "com.scatterednotes.app.tests.chosen"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.hasChosenNotesFolder)
        settings.notesDirectoryURL = FileManager.default.temporaryDirectory
        XCTAssertTrue(settings.hasChosenNotesFolder)
    }

    @MainActor
    func testProjectPersonAndTagSelectionsListOnlyTheirOwnNotes() {
        let launch = Note(title: "Launch", content: "Plan with @Ana", categoryType: .project, targetName: "Website")
        let other = Note(title: "Other", categoryType: .project, targetName: "Garden")
        let gym = Note(title: "Gym", content: "Knee physio #Health", tags: ["Health"])
        let inbox = Note(title: "Errands", content: "email ana@example.com")
        let notes = [launch, other, gym, inbox]

        XCTAssertEqual(notes.filter(SidebarSelection.project(name: "Website").contains).map(\.title), ["Launch"])
        XCTAssertEqual(notes.filter(SidebarSelection.person(name: "ana").contains).map(\.title), ["Launch"])
        XCTAssertEqual(notes.filter(SidebarSelection.tag(name: "health").contains).map(\.title), ["Gym"])
        XCTAssertEqual(notes.filter(SidebarSelection.inbox.contains).map(\.title), ["Gym", "Errands"])
        XCTAssertEqual(notes.filter(SidebarSelection.all.contains).count, 4)
        XCTAssertTrue(SidebarSelection.project(name: "Website").hasOwnDashboard)
        XCTAssertTrue(SidebarSelection.person(name: "Ana").hasOwnDashboard)
        XCTAssertTrue(SidebarSelection.tag(name: "health").hasOwnDashboard)
        XCTAssertFalse(SidebarSelection.dashboard.hasOwnDashboard)
        XCTAssertFalse(SidebarSelection.inbox.hasOwnDashboard)
    }
}
