import XCTest
@testable import ScatteredNotes

/// Guards against losing or corrupting notes: lossless file round trips, crash leftovers,
/// and the rule that merely opening the app never rewrites a note file.
final class DataSafetyTests: XCTestCase {
    // MARK: - Helpers
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private let nastyPieces = [
        "---", "--- ", "----", "\n", "\n\n", "\r\n", "title: x", "id: nope", "type: project", "\"", "\\", "\\\"",
        "'", ":", "#tag", "- [ ] todo", "- [x] done", "---\ntitle: fake\n---", "emoji 🍅🚀", "日本語", "é", "\t",
        "   ", "[]", "tags: [\"a\"]", "<!-- c -->", "```", "a---b", "%", "{{}}", "\u{0}", "\u{2028}"
    ]

    private func randomText(_ rng: inout SeededGenerator, maxPieces: Int = 14) -> String {
        (0..<Int.random(in: 0...maxPieces, using: &rng))
            .map { _ in nastyPieces.randomElement(using: &rng)! }
            .joined(separator: Bool.random(using: &rng) ? "" : " ")
    }

    @MainActor
    private func makeManager(root: URL) -> NoteStorageManager {
        let suite = "com.scatterednotes.app.tests.safety.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return NoteStorageManager(settings: AppSettings(notesDirectoryURL: root, defaults: defaults), enableFileWatcher: false)
    }

    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func mdFiles(in root: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "md" }
    }

    // MARK: - Serialization round trip
    func testRoundTripPreservesContentAndTitleExactly() {
        var rng = SeededGenerator(state: 42)
        for i in 0..<3000 {
            let note = Note(
                title: randomText(&rng, maxPieces: 5).replacingOccurrences(of: "\u{0}", with: ""),
                content: randomText(&rng),
                categoryType: [.inbox, .project, .area].randomElement(using: &rng)!,
                targetName: Bool.random(using: &rng) ? "Proj \(i)" : nil,
                isPinned: Bool.random(using: &rng)
            )
            let parsed = Note.parse(from: note.serializeToMarkdown())
            XCTAssertEqual(parsed.content, note.content, "content changed in iteration \(i): \(note.content.debugDescription)")
            XCTAssertEqual(parsed.id, note.id, "id changed in iteration \(i)")
            XCTAssertEqual(parsed.categoryType, note.categoryType)
            XCTAssertEqual(parsed.isPinned, note.isPinned)
            // Blank titles are replaced by the first line of the body on load, by design
            if !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                XCTAssertEqual(parsed.title.unicodeScalars.map(\.value), note.title.unicodeScalars.map(\.value), "title changed in iteration \(i): \(note.title.debugDescription)")
            }
        }
    }

    func testRepeatedSaveLoadCyclesAreStable() {
        var note = Note(title: "He said \"hi\" \\ --- ok", content: "---\nbody\n\n\n")
        let first = note.serializeToMarkdown()
        for _ in 0..<50 {
            note = Note.parse(from: note.serializeToMarkdown())
        }
        XCTAssertEqual(note.serializeToMarkdown(), first, "title or body drifts with every save")
    }

    func testTitleContainingDelimiterDoesNotLeakIntoBody() {
        let note = Note(title: "Plan --- phase 2", content: "real body")
        let parsed = Note.parse(from: note.serializeToMarkdown())
        XCTAssertEqual(parsed.title, "Plan --- phase 2")
        XCTAssertEqual(parsed.content, "real body")
    }

    func testBodyKeepsLeadingAndTrailingBlankLines() {
        let note = Note(title: "t", content: "\n\nstart\nend\n\n")
        XCTAssertEqual(Note.parse(from: note.serializeToMarkdown()).content, "\n\nstart\nend\n\n")
    }

    func testLegacyFilesStillParse() {
        let legacy = """
        ---
        id: 02EFF95A-FF15-4719-990A-0A091ABE49F6
        title: "Old \\"quoted\\" title"
        type: project
        target: "dsa"
        created_at: 2026-10-26T10:00:00.000Z
        updated_at: 2026-10-26T11:00:00.000Z
        pinned: true
        tags: ["a", "b"]
        ---

        Body line 1
        --- not frontmatter
        Body line 3
        """
        let note = Note.parse(from: legacy)
        XCTAssertEqual(note.title, "Old \"quoted\" title")
        XCTAssertEqual(note.targetName, "dsa")
        XCTAssertTrue(note.isPinned)
        XCTAssertEqual(note.tags, ["a", "b"])
        XCTAssertEqual(note.content, "Body line 1\n--- not frontmatter\nBody line 3")
    }

    func testTextWithoutFrontmatterIsKeptWhole() {
        for raw in ["plain text", "--- \nhr only\nno closing", "---\nunterminated: yes", "", "---", "----\ntext\n----\nmore"] {
            XCTAssertEqual(Note.parse(from: raw).content, raw, "lost text of \(raw.debugDescription)")
        }
    }

    // MARK: - Disk behaviour
    @MainActor
    func testManySavesAllSurviveAFreshLoad() throws {
        let root = makeRoot()
        let manager = makeManager(root: root)
        var rng = SeededGenerator(state: 7)
        var expected: [UUID: String] = [:]

        var notes: [Note] = (0..<25).map { manager.createNote(title: "Note \($0)", content: "seed \($0)") }
        for round in 0..<200 {
            let index = Int.random(in: 0..<notes.count, using: &rng)
            var note = notes[index]
            note.content = randomText(&rng) + " round \(round)"
            manager.save(note: note)
            notes[index] = manager.notes.first { $0.id == note.id }!
        }
        for note in notes { expected[note.id] = note.content }

        // Simulates a crash and relaunch: a brand new manager reads only what is on disk
        let reloaded = makeManager(root: root)
        XCTAssertEqual(reloaded.notes.count, 25)
        XCTAssertEqual(mdFiles(in: root).count, 25)
        for note in reloaded.notes {
            XCTAssertEqual(note.content, expected[note.id], "note \(note.title) differs after reload")
        }
    }

    @MainActor
    func testNotesLeftInAreasMoveToTheInboxAsTags() throws {
        let root = makeRoot()
        let fm = FileManager.default
        let home = root.appendingPathComponent("Areas/Home Office", isDirectory: true)
        let empty = root.appendingPathComponent("Areas/ideas", isDirectory: true)
        let kept = root.appendingPathComponent("Areas/Scans", isDirectory: true)
        for dir in [home, empty, kept] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        try Data("{\"icon\":\"heart.fill\"}".utf8).write(to: empty.appendingPathComponent(".metadata.json"))
        try Data("not a note".utf8).write(to: kept.appendingPathComponent("scan.pdf"))
        let desk = Note(title: "Desk", content: "Buy a lamp\n", categoryType: .area, targetName: "Home Office")
        try desk.serializeToMarkdown().write(to: home.appendingPathComponent("desk.md"), atomically: true, encoding: .utf8)
        let tagged = Note(title: "Chair", content: "Fix the chair #home-office", categoryType: .area, targetName: "Home Office")
        try tagged.serializeToMarkdown().write(to: home.appendingPathComponent("chair.md"), atomically: true, encoding: .utf8)

        let manager = makeManager(root: root)

        let moved = try XCTUnwrap(manager.notes.first { $0.id == desk.id })
        XCTAssertEqual(moved.categoryType, .inbox)
        XCTAssertEqual(moved.content, "Buy a lamp\n\n#home-office")
        XCTAssertEqual(moved.tags, ["home-office"])
        XCTAssertEqual(moved.filePath?.deletingLastPathComponent().path, manager.inboxURL.path)
        let chair = try XCTUnwrap(manager.notes.first { $0.id == tagged.id })
        XCTAssertEqual(chair.content, "Fix the chair #home-office", "a tag already there isn't added twice")
        XCTAssertEqual(mdFiles(in: root).count, 2)
        XCTAssertFalse(fm.fileExists(atPath: home.path))
        XCTAssertFalse(fm.fileExists(atPath: empty.path))
        XCTAssertTrue(fm.fileExists(atPath: kept.appendingPathComponent("scan.pdf").path), "other files are never removed")

        let reloaded = makeManager(root: root)
        XCTAssertEqual(Set(reloaded.notes.map(\.id)), [desk.id, tagged.id])
        XCTAssertTrue(reloaded.notes.allSatisfy { $0.categoryType == .inbox })
    }

    @MainActor
    func testMovingNotesBetweenFoldersNeverLosesOrDuplicatesThem() throws {
        let root = makeRoot()
        let manager = makeManager(root: root)
        manager.createProject(name: "Alpha")
        manager.createProject(name: "Beta")
        var note = manager.createNote(title: "Traveller", content: "keep me --- safe\n- [ ] item")
        var rng = SeededGenerator(state: 99)

        for _ in 0..<40 {
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: manager.move(note: note, to: .inbox, targetName: nil)
            case 1: manager.move(note: note, to: .project, targetName: "Alpha")
            default: manager.move(note: note, to: .project, targetName: "Beta")
            }
            note = try XCTUnwrap(manager.notes.first { $0.id == note.id })
            XCTAssertEqual(mdFiles(in: root).count, 1, "move left a duplicate or lost the file")
            XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(note.filePath).path))
        }

        let reloaded = makeManager(root: root)
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes[0].content, "keep me --- safe\n- [ ] item")
        XCTAssertEqual(reloaded.notes[0].categoryType, note.categoryType)
    }

    @MainActor
    func testLoadingNeverRewritesExistingFiles() throws {
        let root = makeRoot()
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let samples: [String: Data] = [
            "no-frontmatter.md": Data("just text\n--- \nmore".utf8),
            "broken-frontmatter.md": Data("---\ntitle: \"oops\nid: not-a-uuid\n".utf8),
            "crlf.md": Data("---\r\ntitle: \"crlf\"\r\n---\r\n\r\nbody\r\n".utf8),
            "empty.md": Data(),
            "invalid-utf8.md": Data([0xFF, 0xFE, 0x00, 0x41, 0xC3, 0x28]),
            "legacy.md": Data("---\nid: 02EFF95A-FF15-4719-990A-0A091ABE49F6\ntitle: \"Legacy\"\n---\n\nhello\n\n\n".utf8)
        ]
        for (name, data) in samples { try data.write(to: inbox.appendingPathComponent(name)) }

        let manager = makeManager(root: root)
        manager.loadAll()
        manager.loadAll()

        for (name, data) in samples {
            XCTAssertEqual(try Data(contentsOf: inbox.appendingPathComponent(name)), data, "\(name) was modified by loading")
        }
        XCTAssertEqual(mdFiles(in: root).count, samples.count, "a file was added or removed by loading")
    }

    @MainActor
    func testUnreadableFileSurvivesOtherNotesBeingSaved() throws {
        let root = makeRoot()
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let garbage = Data([0xFF, 0xFE, 0xFD, 0xC3, 0x28])
        try garbage.write(to: inbox.appendingPathComponent("2026-01-01_garbled.md"))

        let manager = makeManager(root: root)
        for i in 0..<10 { manager.createNote(title: "n\(i)", content: "c\(i)") }

        XCTAssertEqual(try Data(contentsOf: inbox.appendingPathComponent("2026-01-01_garbled.md")), garbage)
    }

    @MainActor
    func testCrashLeftoversDoNotBreakOrDuplicateNotes() throws {
        let root = makeRoot()
        let manager = makeManager(root: root)
        let note = manager.createNote(title: "Survivor", content: "important")
        let file = try XCTUnwrap(note.filePath)

        // Leftovers a crash can leave behind: temp files from an atomic write, and a note copied
        // to a second folder halfway through a move
        try Data("partial".utf8).write(to: file.deletingLastPathComponent().appendingPathComponent(".Survivor.md.sb-1234-abcd"))
        try Data("partial".utf8).write(to: file.deletingLastPathComponent().appendingPathComponent("tmp.md.partial"))
        manager.createProject(name: "Alpha")
        let copyDir = root.appendingPathComponent("Projects/Alpha", isDirectory: true)
        try FileManager.default.copyItem(at: file, to: copyDir.appendingPathComponent(file.lastPathComponent))

        let reloaded = makeManager(root: root)
        XCTAssertEqual(reloaded.notes.count, 1, "duplicate copy shows twice")
        XCTAssertEqual(reloaded.notes.first?.content, "important")
        XCTAssertEqual(Set(reloaded.notes.map(\.id)).count, reloaded.notes.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyDir.appendingPathComponent(file.lastPathComponent).path), "loader must not delete the extra copy")
    }

    @MainActor
    func testOpeningANoteWithoutMarkersNeverRewritesIt() throws {
        let root = makeRoot()
        let manager = makeManager(root: root)
        let note = manager.createNote(title: "Plans", content: "x")
        let file = try XCTUnwrap(note.filePath)
        let written = "---\nid: \(note.id)\ntitle: Plans\n---\n\nbuy tomatoes today\n- [x] call bank tomorrow\n"
        try written.write(to: file, atomically: true, encoding: .utf8)

        let reloaded = makeManager(root: root)

        XCTAssertEqual(reloaded.agendaItems(for: reloaded.notes[0]).count, 2)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), written, "opening a note rewrote its file")
    }

    @MainActor
    func testDeletingOneNoteLeavesAllOthersIntact() throws {
        let root = makeRoot()
        let manager = makeManager(root: root)
        let keep = (0..<5).map { manager.createNote(title: "same title", content: "body \($0)") }
        let doomed = manager.createNote(title: "same title", content: "delete me")

        manager.delete(note: doomed)

        let reloaded = makeManager(root: root)
        XCTAssertEqual(Set(reloaded.notes.map(\.content)), Set(keep.map(\.content)))
    }

    @MainActor
    func testSameTitleNotesGetSeparateFiles() throws {
        let root = makeRoot()
        let manager = makeManager(root: root)
        for i in 0..<30 { manager.createNote(title: "Untitled Note", content: "n\(i)") }

        XCTAssertEqual(mdFiles(in: root).count, 30, "a note overwrote another one's file")
        XCTAssertEqual(Set(makeManager(root: root).notes.map(\.content)).count, 30)
    }
}
