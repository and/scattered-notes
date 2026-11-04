import XCTest
@testable import ScatteredNotes

final class RecentNotesTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ minutes: Int) -> Note {
        Note(title: "n\(minutes)", updatedAt: base.addingTimeInterval(Double(minutes) * 60))
    }

    func testTakesTheFiveLastEditedNewestFirst() {
        let notes = (1...8).map(note)
        let recent = RecentNotes.latest(notes, hidden: [:])
        XCTAssertEqual(recent.map(\.title), ["n8", "n7", "n6", "n5", "n4"])
    }

    func testFewerThanFiveShowsAll() {
        XCTAssertEqual(RecentNotes.latest([note(1), note(2)], hidden: [:]).count, 2)
        XCTAssertTrue(RecentNotes.latest([], hidden: [:]).isEmpty)
    }

    func testARemovedNoteIsReplacedByTheNextOne() {
        let notes = (1...7).map(note)
        let hidden = [notes[6].id: notes[6].updatedAt]
        let recent = RecentNotes.latest(notes, hidden: hidden)
        XCTAssertEqual(recent.map(\.title), ["n6", "n5", "n4", "n3", "n2"])
    }

    func testARemovedNoteComesBackWhenEditedAgain() {
        var edited = note(3)
        let hidden = [edited.id: edited.updatedAt]
        XCTAssertTrue(RecentNotes.latest([edited], hidden: hidden).isEmpty)
        edited.updatedAt = edited.updatedAt.addingTimeInterval(60)
        XCTAssertEqual(RecentNotes.latest([edited], hidden: hidden).count, 1)
    }

    @MainActor
    func testRemovedNotesAreRememberedAcrossLaunches() {
        let suite = "recent-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let edited = Date(timeIntervalSince1970: 1_800_000_000)
        let folder = FileManager.default.temporaryDirectory
        AppSettings(notesDirectoryURL: folder, defaults: defaults).hiddenRecents[id] = edited
        XCTAssertEqual(AppSettings(notesDirectoryURL: folder, defaults: defaults).hiddenRecents[id], edited)
    }
}
