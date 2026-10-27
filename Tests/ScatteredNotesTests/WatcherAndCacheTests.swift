import XCTest
@testable import ScatteredNotes

/// The folder watcher must notice edits inside subfolders (synced from another device), reloads must
/// only re-read changed files, and cached agenda items must never go stale.
final class WatcherAndCacheTests: XCTestCase {
    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    @MainActor
    private func makeManager(root: URL, watch: Bool = false) -> NoteStorageManager {
        let suite = "com.scatterednotes.app.tests.watcher.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let manager = NoteStorageManager(settings: AppSettings(notesDirectoryURL: root, defaults: defaults), enableFileWatcher: watch)
        addTeardownBlock { await MainActor.run { manager.stopWatching() } }
        return manager
    }

    /// Waits for `condition` while letting the main queue run, as the watcher delivers on it.
    @MainActor
    private func waitUntil(timeout: TimeInterval = 10, _ condition: @MainActor () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    @MainActor
    func testWatcherPicksUpNoteSyncedIntoSubfolder() throws {
        let root = makeRoot()
        let manager = makeManager(root: root, watch: true)
        XCTAssertTrue(manager.notes.isEmpty)

        // As iCloud or OneDrive would deliver a note written on another device
        let synced = Note(title: "From the PC", content: "- [ ] call bank tomorrow")
        try synced.serializeToMarkdown().write(to: manager.inboxURL.appendingPathComponent("2026-10-27_From-the-PC.md"), atomically: true, encoding: .utf8)
        XCTAssertTrue(waitUntil { manager.notes.contains { $0.id == synced.id } }, "new note in Inbox/ not picked up")
        XCTAssertEqual(manager.agendaItems.map(\.text), ["call bank tomorrow"])

        // An edit to an existing note inside a project folder
        manager.createProject(name: "Alpha")
        let note = manager.createNote(title: "Plan", content: "v1", category: .project, targetName: "Alpha")
        let file = try XCTUnwrap(note.filePath)
        RunLoop.main.run(until: Date().addingTimeInterval(0.7)) // past the app's own-write quiet period
        var edited = note
        edited.content = "v2 edited elsewhere"
        try edited.serializeToMarkdown().write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(waitUntil { manager.notes.first { $0.id == note.id }?.content == "v2 edited elsewhere" }, "edit in Projects/Alpha not picked up")
    }

    @MainActor
    func testReloadReadsChangedFilesEvenWithSameSize() throws {
        let root = makeRoot()
        let manager = makeManager(root: root)
        let note = manager.createNote(title: "Same size", content: "aaaa")
        let file = try XCTUnwrap(note.filePath)

        var edited = note
        edited.content = "bbbb"
        try edited.serializeToMarkdown().write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        manager.loadAll()

        XCTAssertEqual(manager.notes.first?.content, "bbbb")
    }

    @MainActor
    func testDeletedFileDisappearsOnReload() throws {
        let root = makeRoot()
        let manager = makeManager(root: root)
        let note = manager.createNote(title: "Gone soon", content: "x")
        try FileManager.default.removeItem(at: XCTUnwrap(note.filePath))
        manager.loadAll()
        XCTAssertTrue(manager.notes.isEmpty)
    }

    @MainActor
    func testCachedAgendaFollowsEveryChange() throws {
        let root = makeRoot()
        let manager = makeManager(root: root)
        var note = manager.createNote(title: "Errands", content: "- [ ] buy stamps\npost letter tomorrow")
        XCTAssertEqual(manager.agendaItems.map(\.text), ["buy stamps", "post letter tomorrow"])
        XCTAssertEqual(manager.agendaItems.map(\.text), ["buy stamps", "post letter tomorrow"], "second read differs")

        note.content += "\n- [ ] new item"
        manager.save(note: note)
        XCTAssertEqual(manager.agendaItems.map(\.text), ["buy stamps", "post letter tomorrow", "new item"])

        manager.toggleChecklistItem(noteID: note.id, lineIndex: 0)
        XCTAssertEqual(manager.agendaItems.filter(\.isDone).map(\.text), ["buy stamps"])

        let other = manager.createNote(title: "Other", content: "- [ ] second note")
        XCTAssertEqual(Set(manager.agendaItems.map(\.text)), ["buy stamps", "post letter tomorrow", "new item", "second note"])

        manager.delete(note: other)
        XCTAssertFalse(manager.agendaItems.contains { $0.text == "second note" })
        XCTAssertEqual(manager.agendaItems(for: try XCTUnwrap(manager.notes.first)).count, 3)
    }
}
