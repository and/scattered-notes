import XCTest
@testable import ScatteredNotes

/// How long the phone's first screens wait for the notes. Prints the timings; fails only when a
/// load is far slower than it should be, so a slow device or a busy machine does not trip it.
final class LoadTimeTests: XCTestCase {
    private func makeVault(notes count: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sn-load-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Inbox"), withIntermediateDirectories: true)
        let projects = ["Work", "Home", "Ideas", "Reading", "Travel"]
        for project in projects {
            try fm.createDirectory(at: root.appendingPathComponent("Projects/\(project)"), withIntermediateDirectories: true)
        }
        let body = String(repeating: "A line of ordinary text that a note might hold, with a few words in it.\n", count: 8)
        for index in 0..<count {
            let id = UUID()
            let folder = index % 3 == 0 ? "Inbox" : "Projects/\(projects[index % projects.count])"
            let type = folder == "Inbox" ? "inbox" : "project"
            let target = folder == "Inbox" ? "" : "target: \"\(projects[index % projects.count])\"\n"
            let text = """
            ---
            id: \(id.uuidString)
            title: "Note \(index)"
            type: \(type)
            \(target)created_at: 2026-10-\(String(format: "%02d", 1 + index % 28))T09:00:00Z
            updated_at: 2026-10-\(String(format: "%02d", 1 + index % 28))T09:00:00Z
            ---

            \(body)- [ ] call someone tomorrow
            - [x] pay the bill ✅ 2026-10-20
            buy milk on friday
            #tag\(index % 20) @person\(index % 30)
            """
            try text.write(to: root.appendingPathComponent(folder).appendingPathComponent("\(index)-\(id.uuidString.prefix(8)).md"),
                           atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? fm.removeItem(at: root) }
        return root
    }

    private func time<T>(_ label: String, _ work: () -> T) -> (T, TimeInterval) {
        let start = Date()
        let result = work()
        let elapsed = Date().timeIntervalSince(start)
        print("LOADTIME \(label): \(String(format: "%.0f", elapsed * 1000)) ms")
        return (result, elapsed)
    }

    @MainActor
    func testFirstScreensOfALargeVault() throws {
        let count = 2_000
        let root = try makeVault(notes: count)
        let suite = "com.scatterednotes.app.tests.loadtime"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let (manager, cold) = time("launch: read \(count) notes") {
            NoteStorageManager(settings: AppSettings(notesDirectoryURL: root, defaults: defaults), enableFileWatcher: false)
        }
        XCTAssertEqual(manager.notes.count, count)
        _ = time("reload with nothing changed") { manager.loadAll() }

        let (items, _) = time("Dashboard: agenda items of every note") { manager.agendaItems }
        let today = Calendar.current.startOfDay(for: Date())
        _ = time("Dashboard: build the sections") {
            DashboardSnapshot(notes: manager.notes, items: items, today: today, upcomingDays: 14, calendar: .current)
        }
        _ = time("Dashboard again, nothing changed") { manager.agendaItems }
        XCTAssertLessThan(cold, 30, "reading \(count) notes took \(cold) s")
        XCTAssertEqual(manager.loadStats.loadCount, 2, "the launch load and the reload")
        XCTAssertGreaterThan(manager.loadStats.firstLoadMilliseconds, 0)
        XCTAssertGreaterThan(manager.loadStats.agendaMilliseconds, 0)
    }
}
