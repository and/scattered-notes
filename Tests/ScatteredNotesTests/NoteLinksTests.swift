import XCTest
@testable import ScatteredNotes

final class NoteLinksTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ title: String, _ content: String = "", minutes: Int = 0) -> Note {
        Note(title: title, content: content, updatedAt: base.addingTimeInterval(Double(minutes) * 60))
    }

    private func targets(_ index: NoteLinkIndex, from note: Note) -> [UUID?] {
        index.links(from: note.id).map(\.target)
    }

    // MARK: Titles in the running text

    func testFindsAnotherNotesTitleInTheText() {
        let budget = note("Budget")
        let plan = note("Plan", "Check the budget before Friday")
        let index = NoteLinkIndex(notes: [budget, plan])
        let links = index.links(from: plan.id)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].target, budget.id)
        XCTAssertEqual(links[0].text, "budget")
        XCTAssertFalse(links[0].isExplicit)
        XCTAssertEqual((plan.content as NSString).substring(with: links[0].range), "budget")
    }

    func testMatchesWholeWordsOnly() {
        let plan = note("Plan")
        let other = note("Other", "planning the planets, a plant")
        let index = NoteLinkIndex(notes: [plan, other])
        XCTAssertTrue(index.links(from: other.id).isEmpty)
    }

    func testIgnoresCaseAndAccents() {
        let cafe = note("Café Notes")
        let other = note("Other", "met at the CAFE NOTES place")
        let index = NoteLinkIndex(notes: [cafe, other])
        XCTAssertEqual(targets(index, from: other), [cafe.id])
    }

    func testPunctuationBetweenWordsDoesNotMatter() {
        let title = note("Plan: Q4")
        let other = note("Other", "the plan Q4 review, and plan - Q4 again")
        let index = NoteLinkIndex(notes: [title, other])
        XCTAssertEqual(targets(index, from: other), [title.id, title.id])
    }

    func testTheLongestTitleWinsAndUsesUpTheText() {
        let short = note("Garden")
        let long = note("Garden Party")
        let other = note("Other", "the garden party is on Friday, the garden is wet")
        let index = NoteLinkIndex(notes: [short, long, other])
        let links = index.links(from: other.id)
        XCTAssertEqual(links.map(\.target), [long.id, short.id])
        XCTAssertEqual(links.map(\.text), ["garden party", "garden"])
    }

    func testTitlesSharingTheFirstWordAreToldApart() {
        let one = note("Trip to Goa")
        let two = note("Trip to Pune")
        let bare = note("Trip")
        let other = note("Other", "trip to pune, trip to goa, a trip to Delhi")
        let links = NoteLinkIndex(notes: [one, two, bare, other]).links(from: other.id)
        XCTAssertEqual(links.map(\.target), [two.id, one.id, bare.id])
    }

    func testTitlesShorterThanThreeCharactersAreNotLookedFor() {
        let tiny = note("Go")
        let other = note("Other", "go to the shop")
        XCTAssertTrue(NoteLinkIndex(notes: [tiny, other]).links(from: other.id).isEmpty)
    }

    func testANoteDoesNotLinkToItself() {
        let budget = note("Budget", "The budget is tight")
        XCTAssertTrue(NoteLinkIndex(notes: [budget]).links(from: budget.id).isEmpty)
    }

    func testTwoNotesWithTheSameTitleBothGetTheLink() {
        let first = note("Ideas")
        let second = note("Ideas")
        let other = note("Other", "More ideas for the site")
        let index = NoteLinkIndex(notes: [first, second, other])
        XCTAssertEqual(Set(targets(index, from: other)), [first.id, second.id])
    }

    func testAnUntitledNoteIsNotFoundByItsPlaceholder() {
        let blank = note("")
        let other = note("Other", "an untitled note is here")
        XCTAssertTrue(NoteLinkIndex(notes: [blank, other]).links(from: other.id).isEmpty)
    }

    func testTheTitleOfANoteWithoutOneIsItsFirstLine() {
        let untitled = note("", "Holiday packing\n- socks")
        let other = note("Other", "see holiday packing")
        XCTAssertEqual(targets(NoteLinkIndex(notes: [untitled, other]), from: other), [untitled.id])
    }

    func testLinksComeInTheOrderOfTheText() {
        let a = note("Alpha")
        let b = note("Bravo")
        let other = note("Other", "bravo first, then alpha")
        XCTAssertEqual(targets(NoteLinkIndex(notes: [a, b, other]), from: other), [b.id, a.id])
    }

    func testRangesCountUTF16SoEmojiBeforeATitleDoNotShiftThem() {
        let budget = note("Budget")
        let other = note("Other", "🙂🙂 budget")
        let link = NoteLinkIndex(notes: [budget, other]).links(from: other.id)[0]
        XCTAssertEqual((other.content as NSString).substring(with: link.range), "budget")
    }

    // MARK: [[Title]]

    func testExplicitLinkFindsTheNote() {
        let budget = note("Budget")
        let other = note("Other", "see [[Budget]] now")
        let links = NoteLinkIndex(notes: [budget, other]).links(from: other.id)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].target, budget.id)
        XCTAssertTrue(links[0].isExplicit)
        XCTAssertEqual((other.content as NSString).substring(with: links[0].range), "[[Budget]]")
    }

    func testExplicitLinkIsNotAlsoCountedAsAPlainMention() {
        let budget = note("Budget")
        let other = note("Other", "[[Budget]] and the budget")
        let links = NoteLinkIndex(notes: [budget, other]).links(from: other.id)
        XCTAssertEqual(links.map(\.isExplicit), [true, false])
    }

    func testExplicitLinkToAMissingNoteHasNoTarget() {
        let other = note("Other", "see [[Nowhere]]")
        let links = NoteLinkIndex(notes: [other]).links(from: other.id)
        XCTAssertEqual(links.count, 1)
        XCTAssertNil(links[0].target)
        XCTAssertEqual(links[0].text, "Nowhere")
    }

    func testExplicitLinkWorksForShortTitlesAndIgnoresCase() {
        let go = note("Go")
        let other = note("Other", "[[go]]")
        XCTAssertEqual(targets(NoteLinkIndex(notes: [go, other]), from: other), [go.id])
    }

    func testAnExplicitLinkToYourselfIsDropped() {
        let me = note("Me", "[[Me]]")
        XCTAssertTrue(NoteLinkIndex(notes: [me]).links(from: me.id).isEmpty)
    }

    func testBracketsAcrossLinesAreNotALink() {
        let budget = note("Budget")
        let other = note("Other", "[[Bud\nget]]")
        XCTAssertTrue(NoteLinkIndex(notes: [budget, other]).links(from: other.id).isEmpty)
    }

    // MARK: Making a mention a link

    func testAMentionBecomesAnExplicitLinkToTheSameNote() throws {
        let budget = note("Budget")
        let other = note("Other", "🙂 check the budget first, then the budget again")
        let link = try XCTUnwrap(NoteLinkIndex(notes: [budget, other]).links(from: other.id).first)
        let changed = try XCTUnwrap(NoteLinkIndex.makingExplicit(link, title: "Budget", in: other.content))
        XCTAssertEqual(changed, "🙂 check the [[Budget]] first, then the budget again")

        var edited = other
        edited.content = changed
        let after = NoteLinkIndex(notes: [budget, edited]).links(from: other.id)
        XCTAssertEqual(after.map(\.isExplicit), [true, false], "the first is now written as a link, the second is still plain")
        XCTAssertEqual(after.map(\.target), [budget.id, budget.id])
    }

    func testTitlesThatCannotBeWrittenAsALinkAreRefused() {
        XCTAssertNil(NoteLinkIndex.explicitText(forTitle: "Plan [draft]"))
        XCTAssertNil(NoteLinkIndex.explicitText(forTitle: "Two\nlines"))
        XCTAssertNil(NoteLinkIndex.explicitText(forTitle: ""))
        XCTAssertEqual(NoteLinkIndex.explicitText(forTitle: "Plan: Q4"), "[[Plan: Q4]]")
    }

    func testAnExplicitLinkOrAStaleRangeIsNotRewritten() throws {
        let budget = note("Budget")
        let other = note("Other", "[[Budget]]")
        let link = try XCTUnwrap(NoteLinkIndex(notes: [budget, other]).links(from: other.id).first)
        XCTAssertNil(NoteLinkIndex.makingExplicit(link, title: "Budget", in: other.content))

        let plain = note("Plain", "the budget")
        let mention = try XCTUnwrap(NoteLinkIndex(notes: [budget, plain]).links(from: plain.id).first)
        XCTAssertNil(NoteLinkIndex.makingExplicit(mention, title: "Budget", in: "tiny"), "the text is shorter than the range")
    }

    // MARK: Backlinks

    func testBacklinksListEachLinkingNoteOnceNewestFirst() {
        let budget = note("Budget", minutes: 0)
        let older = note("Older", "budget, budget and [[Budget]]", minutes: 1)
        let newer = note("Newer", "the budget", minutes: 5)
        let unrelated = note("Unrelated", "nothing here", minutes: 9)
        let index = NoteLinkIndex(notes: [budget, older, newer, unrelated])
        XCTAssertEqual(index.backlinks(to: budget.id), [newer.id, older.id])
        XCTAssertTrue(index.backlinks(to: unrelated.id).isEmpty)
    }

    func testLinkedNotesListsEachTargetOnceInOrder() {
        let a = note("Alpha")
        let b = note("Bravo")
        let other = note("Other", "alpha, bravo, alpha again")
        XCTAssertEqual(NoteLinkIndex(notes: [a, b, other]).linkedNotes(from: other.id), [a.id, b.id])
    }

    func testRenamingANoteMovesItsBacklinks() {
        var budget = note("Budget")
        let other = note("Other", "the budget")
        XCTAssertEqual(NoteLinkIndex(notes: [budget, other]).backlinks(to: budget.id), [other.id])
        budget.title = "Money"
        XCTAssertTrue(NoteLinkIndex(notes: [budget, other]).backlinks(to: budget.id).isEmpty)
    }

    func testNoNotesAndEmptyTextGiveNothing() {
        XCTAssertTrue(NoteLinkIndex(notes: []).links(from: UUID()).isEmpty)
        let empty = note("Empty")
        XCTAssertTrue(NoteLinkIndex(notes: [empty]).links(from: empty.id).isEmpty)
    }

    func testManyNotesStayFast() {
        let notes = (0..<2000).map { note("Topic number \($0)", String(repeating: "word another thing here ", count: 40) + "topic number \($0 / 2)") }
        measure { _ = NoteLinkIndex(notes: notes) }
    }
}
