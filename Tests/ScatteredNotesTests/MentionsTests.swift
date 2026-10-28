import XCTest
@testable import ScatteredNotes

final class MentionsTests: XCTestCase {
    func testFindsPeopleTagsAndProjectsAtTheStartOfWords() {
        let text = "Call @Ana about +Website (#idea), then #idea again and @ana."
        XCTAssertEqual(Mentions.names(.person, in: text), ["Ana"])
        XCTAssertEqual(Mentions.names(.tag, in: text), ["idea"])
        XCTAssertEqual(Mentions.names(.project, in: text), ["Website"])
    }

    func testIgnoresSymbolsThatAreNotMarks() {
        let text = "Mail ana@example.com about C# and +91 98450 for #1 ~5 min, x+y"
        XCTAssertTrue(Mentions.marks(in: text).isEmpty)
    }

    func testNamesKeepDashesDotsAndDigitsButNotATrailingDot() {
        XCTAssertEqual(Mentions.names(.tag, in: "#home-office #v2.1 #done."), ["home-office", "v2.1", "done"])
        XCTAssertEqual(Mentions.names(.project, in: "+Q4_launch"), ["Q4_launch"])
    }

    func testNoteTagsAndPeopleComeFromItsText() {
        let note = Note.parse(from: "---\ntags: [\"old\"]\n---\n\nPing @sam #new")
        XCTAssertEqual(note.tags, ["old", "new"])
        XCTAssertEqual(note.people, ["sam"])
    }

    func testAreaNamesBecomeTagNames() {
        XCTAssertEqual(NoteStorageManager.tagName(forArea: "Home Office"), "home-office")
        XCTAssertEqual(NoteStorageManager.tagName(forArea: "ideas"), "ideas")
        XCTAssertEqual(NoteStorageManager.tagName(forArea: "2026 Goals"), "area-2026-goals")
    }

    @MainActor
    func testQuickNoteFilesUnderTheProjectNamedWithPlus() {
        let projects = [ProjectArea(name: "Scattered Notes", type: .project)]
        XCTAssertEqual(QuickCaptureView.inlineProject(in: "fix sync +scatterednotes", projects: projects), "Scattered Notes")
        XCTAssertEqual(QuickCaptureView.inlineProject(in: "plan +garden beds", projects: projects), "Garden")
        XCTAssertNil(QuickCaptureView.inlineProject(in: "ask @ana about #garden", projects: projects))
    }
}
