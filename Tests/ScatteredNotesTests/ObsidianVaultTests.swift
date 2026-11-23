import XCTest
@testable import ScatteredNotes

/// A folder shared with Obsidian: notes at the top and in other folders show up, stay where they are
/// when edited, and nothing is added to the vault that the user did not ask for.
final class ObsidianVaultTests: XCTestCase {
    private func makeVault() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    @MainActor
    private func makeManager(root: URL) -> NoteStorageManager {
        let suite = "com.scatterednotes.app.tests.vault.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return NoteStorageManager(settings: AppSettings(notesDirectoryURL: root, defaults: defaults), enableFileWatcher: false)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    func testVaultNotesShowAndNothingIsAddedOnLaunch() throws {
        let root = try makeVault()
        try write("- [ ] call the bank\n", to: root.appendingPathComponent("Top note.md"))
        try write("- [ ] plan trip\n", to: root.appendingPathComponent("Travel/Japan.md"))
        try write("{}", to: root.appendingPathComponent(".obsidian/app.json"))
        try write("- [ ] hidden\n", to: root.appendingPathComponent(".obsidian/Stray.md"))
        try write("pic", to: root.appendingPathComponent("Attachments/pic.png"))

        let manager = makeManager(root: root)

        XCTAssertEqual(Set(manager.notes.map(\.title)), ["Top note", "Japan"])
        XCTAssertEqual(manager.notes.first { $0.title == "Top note" }?.categoryType, .inbox)
        let japan = try XCTUnwrap(manager.notes.first { $0.title == "Japan" })
        XCTAssertEqual(japan.categoryType, .project)
        XCTAssertEqual(japan.targetName, "Travel")
        XCTAssertEqual(manager.projects.map(\.name), ["Travel"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.inboxURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.projectsURL.path))
    }

    @MainActor
    func testEditedVaultNotesStayWhereTheyAre() throws {
        let root = try makeVault()
        let top = root.appendingPathComponent("Top note.md")
        let japanFile = root.appendingPathComponent("Travel/Japan.md")
        try write("- [ ] call the bank\n", to: top)
        try write("- [ ] plan trip\n", to: japanFile)
        let manager = makeManager(root: root)

        var topNote = try XCTUnwrap(manager.notes.first { $0.title == "Top note" })
        topNote.content += "- [ ] more\n"
        manager.save(note: topNote)
        var japan = try XCTUnwrap(manager.notes.first { $0.title == "Japan" })
        japan.content += "- [ ] more\n"
        manager.save(note: japan)

        let listing = (FileManager.default.enumerator(atPath: root.path)?.allObjects ?? []).map { "\($0)" }.sorted()
        XCTAssertTrue(FileManager.default.fileExists(atPath: top.path), "\(listing) \(topNote.filePath?.path ?? "nil") root=\(root.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: japanFile.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".md") }, ["Top note.md"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.inboxURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.projectsURL.path))
    }

    @MainActor
    func testDeletingLooseProjectKeepsAttachments() throws {
        let root = try makeVault()
        try write("note", to: root.appendingPathComponent("Travel/Japan.md"))
        try write("pic", to: root.appendingPathComponent("Travel/map.png"))
        let manager = makeManager(root: root)

        manager.deleteProject(name: "Travel")

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Travel/Japan.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Travel/map.png").path))
    }

    func testHiddenPathsAreIgnoredByTheWatcher() {
        XCTAssertTrue(FolderWatcher.isHidden("/v/.obsidian/workspace.json", below: "/v"))
        XCTAssertTrue(FolderWatcher.isHidden("/v/.git/index", below: "/v"))
        XCTAssertFalse(FolderWatcher.isHidden("/v/Travel/Japan.md", below: "/v"))
        XCTAssertTrue(FolderWatcher.isHidden("/v/.obsidian/app.json", below: "/v/"))
        // A sibling folder that only starts with the same name is not inside it
        XCTAssertFalse(FolderWatcher.isHidden("/vault2/.git/index", below: "/vault"))
    }
}
