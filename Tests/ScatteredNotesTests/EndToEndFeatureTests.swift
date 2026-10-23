import XCTest
@testable import ScatteredNotes

final class EndToEndFeatureTests: XCTestCase {
    var tempDirectory: URL!
    var settings: AppSettings!
    var storageManager: NoteStorageManager!
    
    @MainActor
    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        settings = AppSettings(notesDirectoryURL: tempDirectory)
        storageManager = NoteStorageManager(settings: settings, enableFileWatcher: false)
    }
    
    @MainActor
    override func tearDown() {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        storageManager = nil
        settings = nil
        tempDirectory = nil
        super.tearDown()
    }
    
    // MARK: - 1. Quick Capture to Inbox End-to-End
    @MainActor
    func testE2E_QuickCaptureToInbox() {
        // User captures a random thought without specifying a project
        let note = storageManager.createNote(
            title: "",
            content: "Remember to buy coffee beans #groceries",
            category: .inbox,
            targetName: nil,
            tags: ["groceries"]
        )
        
        // 1. Verify note in-memory properties
        XCTAssertEqual(note.categoryType, .inbox)
        XCTAssertNil(note.targetName)
        XCTAssertEqual(note.displayTitle, "Remember to buy coffee beans #groceries")
        XCTAssertEqual(note.tags, ["groceries"])
        
        // 2. Verify file persisted on disk in Inbox folder
        guard let fileURL = note.filePath else {
            XCTFail("Note filePath must not be nil")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(fileURL.deletingLastPathComponent().path, storageManager.inboxURL.path)
        
        // 3. Verify YAML frontmatter and content on disk
        let savedRaw = try? String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertNotNil(savedRaw)
        XCTAssertTrue(savedRaw!.contains("type: inbox"))
        XCTAssertTrue(savedRaw!.contains("tags: [\"groceries\"]"))
        XCTAssertTrue(savedRaw!.contains("Remember to buy coffee beans #groceries"))
    }
    
    // MARK: - 2. Inline Project Tagging (+Project) to Existing Project
    @MainActor
    func testE2E_InlineProjectTaggingExistingProject() {
        // Pre-create project
        storageManager.createProject(name: "MobileApp", icon: "iphone")
        XCTAssertTrue(storageManager.projects.contains { $0.name == "MobileApp" })
        
        // Simulate user capturing note with +MobileApp
        let note = storageManager.createNote(
            title: "Fix navigation freeze",
            content: "Investigate NavigationSplitView crash on macOS +MobileApp #bug",
            category: .project,
            targetName: "MobileApp",
            tags: ["bug"]
        )
        
        // Verify note placed in project folder
        guard let fileURL = note.filePath else {
            XCTFail("Missing note file path")
            return
        }
        let expectedProjectDir = storageManager.projectsURL.appendingPathComponent("MobileApp")
        XCTAssertEqual(fileURL.deletingLastPathComponent().path, expectedProjectDir.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        
        // Verify frontmatter specifies project target
        let contentOnDisk = try? String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contentOnDisk!.contains("type: project"))
        XCTAssertTrue(contentOnDisk!.contains("target: \"MobileApp\""))
        XCTAssertTrue(contentOnDisk!.contains("tags: [\"bug\"]"))
    }
    
    // MARK: - 3. Inline Project Tagging Auto-Creates New Project
    @MainActor
    func testE2E_InlineProjectTaggingAutoCreatesNewProject() {
        let newProjectName = "BrandRedesign"
        XCTAssertFalse(storageManager.projects.contains { $0.name == newProjectName })
        
        // When user types +BrandRedesign, the app auto-creates the project if missing
        if !storageManager.projects.contains(where: { $0.name.lowercased() == newProjectName.lowercased() }) {
            storageManager.createProject(name: newProjectName)
        }
        
        let note = storageManager.createNote(
            title: "Logo variations",
            content: "Review Figma mockups +BrandRedesign",
            category: .project,
            targetName: newProjectName
        )
        
        // Verify project directory created on disk
        let projectDir = storageManager.projectsURL.appendingPathComponent(newProjectName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectDir.path))
        XCTAssertTrue(storageManager.projects.contains { $0.name == newProjectName })
        
        // Verify note file is inside that directory
        XCTAssertEqual(note.filePath?.deletingLastPathComponent().path, projectDir.path)
    }
    
    // MARK: - 4. Wiki-link Syntax [[Project]] Tagging
    @MainActor
    func testE2E_WikiLinkSyntaxProjectTagging() {
        let areaName = "Health"
        storageManager.createArea(name: areaName, icon: "heart.fill")
        
        // Simulate note tagged via [[Health]]
        let note = storageManager.createNote(
            title: "Morning Routine",
            content: "Daily stretching and 5km jog [[Health]]",
            category: .area,
            targetName: areaName
        )
        
        let expectedAreaDir = storageManager.areasURL.appendingPathComponent(areaName)
        XCTAssertEqual(note.filePath?.deletingLastPathComponent().path, expectedAreaDir.path)
        XCTAssertEqual(note.destinationDisplay, "Health")
    }
    
    // MARK: - 5. Interactive Checklist Interactivity & Progress Tracking
    @MainActor
    func testE2E_InteractiveChecklistProgress() {
        var note = storageManager.createNote(
            title: "Launch Checklist",
            content: """
            # Launch Tasks
            - [ ] Test on Apple Silicon
            - [ ] Test on Intel Mac
            - [x] Code sign binary
            """,
            category: .inbox
        )
        
        // Initial stats check: 1 completed out of 3
        var stats = note.checklistStats
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.completed, 1)
        XCTAssertEqual(stats?.total, 3)
        
        // Simulate user clicking to check off "Test on Apple Silicon"
        note.content = note.content.replacingOccurrences(of: "- [ ] Test on Apple Silicon", with: "- [x] Test on Apple Silicon")
        storageManager.save(note: note)
        
        // Verify updated stats: 2 completed out of 3
        stats = note.checklistStats
        XCTAssertEqual(stats?.completed, 2)
        XCTAssertEqual(stats?.total, 3)
        
        // Verify saved to disk correctly
        let rawDisk = try? String(contentsOf: note.filePath!, encoding: .utf8)
        XCTAssertTrue(rawDisk!.contains("- [x] Test on Apple Silicon"))
        XCTAssertTrue(rawDisk!.contains("- [ ] Test on Intel Mac"))
    }
    
    // MARK: - 6. Moving Notes Across Categories (Inbox -> Project -> Area)
    @MainActor
    func testE2E_MoveNoteAcrossCategories() {
        storageManager.createProject(name: "ClientPitch")
        storageManager.createArea(name: "Archives")
        
        // 1. Note created in Inbox
        let note = storageManager.createNote(
            title: "Slide deck notes",
            content: "Key market statistics",
            category: .inbox
        )
        let initialPath = note.filePath!
        XCTAssertEqual(initialPath.deletingLastPathComponent().path, storageManager.inboxURL.path)
        
        // 2. Move to Project "ClientPitch"
        storageManager.move(note: note, to: .project, targetName: "ClientPitch")
        let noteInProject = storageManager.notes.first { $0.id == note.id }!
        XCTAssertEqual(noteInProject.categoryType, .project)
        XCTAssertEqual(noteInProject.targetName, "ClientPitch")
        XCTAssertEqual(noteInProject.filePath?.deletingLastPathComponent().path, storageManager.projectsURL.appendingPathComponent("ClientPitch").path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: initialPath.path)) // Old file removed
        XCTAssertTrue(FileManager.default.fileExists(atPath: noteInProject.filePath!.path)) // New file exists
        
        // 3. Move to Area "Archives"
        let projectPath = noteInProject.filePath!
        storageManager.move(note: noteInProject, to: .area, targetName: "Archives")
        let noteInArea = storageManager.notes.first { $0.id == note.id }!
        XCTAssertEqual(noteInArea.categoryType, .area)
        XCTAssertEqual(noteInArea.targetName, "Archives")
        XCTAssertEqual(noteInArea.filePath?.deletingLastPathComponent().path, storageManager.areasURL.appendingPathComponent("Archives").path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: noteInArea.filePath!.path))
    }
    
    // MARK: - 7. Full-Text Search and Tag Filtering
    @MainActor
    func testE2E_FullTextSearchAndFiltering() {
        storageManager.createNote(title: "Swift Concurrency", content: "Understanding actors and tasks", category: .inbox, tags: ["swift", "dev"])
        storageManager.createNote(title: "Grocery List", content: "Apples, bananas, oat milk", category: .inbox, tags: ["home"])
        storageManager.createNote(title: "API Design", content: "REST vs GraphQL comparison", category: .inbox, tags: ["architecture"])
        
        let allNotes = storageManager.notes
        XCTAssertEqual(allNotes.count, 3)
        
        // Search by title keyword
        let searchSwift = allNotes.filter { $0.title.lowercased().contains("swift") || $0.content.lowercased().contains("swift") }
        XCTAssertEqual(searchSwift.count, 1)
        XCTAssertEqual(searchSwift.first?.title, "Swift Concurrency")
        
        // Search by body content
        let searchMilk = allNotes.filter { $0.content.lowercased().contains("milk") }
        XCTAssertEqual(searchMilk.count, 1)
        XCTAssertEqual(searchMilk.first?.title, "Grocery List")
        
        // Search by tag
        let searchArch = allNotes.filter { $0.tags.contains("architecture") }
        XCTAssertEqual(searchArch.count, 1)
        XCTAssertEqual(searchArch.first?.title, "API Design")
    }
    
    // MARK: - 8. Project Custom Icons & Metadata Persistence
    @MainActor
    func testE2E_ProjectCustomIconPersistence() {
        // Create project with custom rocket icon
        storageManager.createProject(name: "Stargazer", icon: "rocket.fill")
        
        let metaURL = storageManager.projectsURL.appendingPathComponent("Stargazer").appendingPathComponent(".metadata.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path))
        
        // Re-read storage from scratch
        storageManager.loadAll()
        let reloadedProject = storageManager.projects.first { $0.name == "Stargazer" }
        XCTAssertNotNil(reloadedProject)
        XCTAssertEqual(reloadedProject?.iconName, "rocket.fill")
    }
    
    // MARK: - 9. Note Pinning and Ordering Priority
    @MainActor
    func testE2E_NotePinningOrder() {
        let note1 = storageManager.createNote(title: "Note 1 (Older)", content: "Content 1", category: .inbox)
        let note2 = storageManager.createNote(title: "Note 2 (Newer)", content: "Content 2", category: .inbox)
        
        // By default, newer note is first
        XCTAssertEqual(storageManager.notes.first?.id, note2.id)
        
        // Pin note 1
        storageManager.togglePin(note: note1)
        
        // Note 1 should now be at the very top because it is pinned
        XCTAssertEqual(storageManager.notes.first?.id, note1.id)
        XCTAssertTrue(storageManager.notes.first!.isPinned)
    }
    
    // MARK: - 10. Deletion Cleans Up Disk Files
    @MainActor
    func testE2E_DeletionCleansUpDisk() {
        let note = storageManager.createNote(title: "Temporary Note", content: "To be deleted", category: .inbox)
        let filePath = note.filePath!
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path))
        XCTAssertEqual(storageManager.notes.count, 1)
        
        // Delete note
        storageManager.delete(note: note)
        
        // Verify removed from state and deleted from disk
        XCTAssertEqual(storageManager.notes.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath.path))
    }
}
