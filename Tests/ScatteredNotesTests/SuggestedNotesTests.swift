import XCTest
@testable import ScatteredNotes

final class SuggestedNotesTests: XCTestCase {
    /// A small made-up word model: each word is a point in 3 dimensions, so meaning is easy to arrange
    private struct Toy: WordVectors {
        let table: [String: [Double]]
        func vector(for word: String) -> [Double]? { table[word] }
    }

    private let toy = Toy(table: [
        "dentist": [1, 0.1, 0], "teeth": [0.9, 0.2, 0], "appointment": [0.5, 0.5, 0],
        "taxes": [0, 0, 1], "invoice": [0, 0.1, 0.9],
        "garden": [0, 1, 0],
    ])

    private func unit(_ text: String) -> [Double]? { SuggestedIndex.vector(for: text, using: toy) }

    func testAVectorIsTheAverageOfItsWordsScaledToLengthOne() throws {
        let vector = try XCTUnwrap(unit("dentist teeth"))
        XCTAssertEqual(vector.reduce(0) { $0 + $1 * $1 }, 1, accuracy: 1e-9)
    }

    func testTextWithNoKnownWordHasNoVector() {
        XCTAssertNil(unit("zzz qqq"))
        XCTAssertNil(unit("dentist"), "one known word is too little to go on")
        XCTAssertNil(unit(""))
        XCTAssertNil(unit("the and for"), "stop words carry nothing")
    }

    func testShortWordsAndNumbersAreIgnored() throws {
        let plain = try XCTUnwrap(unit("dentist dentist"))
        let padded = try XCTUnwrap(unit("dentist 2026 at of 12345 dentist"))
        XCTAssertEqual(plain, padded)
    }

    func testNotesCloseInMeaningAreSuggestedAndFarOnesAreNot() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let index = SuggestedIndex(vectors: [a: try XCTUnwrap(unit("dentist dentist")), b: try XCTUnwrap(unit("teeth appointment")), c: try XCTUnwrap(unit("taxes invoice"))])
        let result = index.suggestions(for: a)
        XCTAssertEqual(result.map(\.id), [b])
        XCTAssertGreaterThan(result[0].similarity, SuggestedIndex.minimumScore)
    }

    func testARareWordCountsMoreThanACommonOne() throws {
        let frequency = ["dentist": 1, "garden": 9]
        let rareWeight = SuggestedIndex.weight(of: "dentist", documentFrequency: frequency, count: 10)
        let commonWeight = SuggestedIndex.weight(of: "garden", documentFrequency: frequency, count: 10)
        XCTAssertGreaterThan(rareWeight, commonWeight)
        // "dentist garden" leans toward the rare word once weighted, and sits level when not
        let weighted = try XCTUnwrap(SuggestedIndex.vector(title: "", body: "dentist garden garden dentist", using: toy,
                                                           weight: { SuggestedIndex.weight(of: $0, documentFrequency: frequency, count: 10) }))
        let plain = try XCTUnwrap(unit("dentist garden garden dentist"))
        let dentist = try XCTUnwrap(unit("dentist dentist"))
        func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
        XCTAssertGreaterThan(dot(weighted, dentist), dot(plain, dentist))
    }

    func testTitleWordsCountDouble() throws {
        let inTitle = try XCTUnwrap(SuggestedIndex.vector(title: "dentist", body: "garden", using: toy))
        let inBody = try XCTUnwrap(SuggestedIndex.vector(title: "garden", body: "dentist", using: toy))
        let dentist = try XCTUnwrap(unit("dentist dentist"))
        func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
        XCTAssertGreaterThan(dot(inTitle, dentist), dot(inBody, dentist))
    }

    func testASharedTagLiftsANoteOverTheLineAndAnUnsharedOneStaysBelow() throws {
        // Two notes about 0.46 alike: just short of the line by themselves
        let a = UUID(), b = UUID(), c = UUID()
        let base = [1.0, 0.0, 0.0]
        let near = [0.46, (1 - 0.46 * 0.46).squareRoot(), 0.0]
        let withoutMarks = SuggestedIndex(vectors: [a: base, b: near])
        XCTAssertTrue(withoutMarks.suggestions(for: a).isEmpty)
        let withMarks = SuggestedIndex(vectors: [a: base, b: near, c: near], marks: [a: ["#home"], b: ["#home"], c: ["#work"]])
        XCTAssertEqual(withMarks.suggestions(for: a).map(\.id), [b], "the note with the shared tag is suggested, the other is not")
    }

    func testTheMarkBonusIsCappedAndAProjectAddsALittle() throws {
        let a = UUID(), b = UUID()
        let v = [1.0, 0.0, 0.0]
        let marks: Set<String> = ["#a", "#b", "#c", "@d"]
        let index = SuggestedIndex(vectors: [a: v, b: v], marks: [a: marks, b: marks], projects: [a: "home", b: "home"])
        let score = try XCTUnwrap(index.suggestions(for: a).first?.score)
        XCTAssertEqual(score, 1 + 2 * SuggestedIndex.sharedMarkBonus + SuggestedIndex.sameProjectBonus, accuracy: 1e-9)
    }

    func testTakingOffTheCommonPartSeparatesNotesThatAllLookAlike() throws {
        // Every vector leans the same way (the big first number); only the small parts tell the notes apart
        let a = UUID(), b = UUID(), c = UUID()
        let index = SuggestedIndex(sums: [a: [10, 1, 0], b: [10, 1.1, 0.1], c: [10, -1, 0]])
        let result = index.suggestions(for: a)
        XCTAssertEqual(result.map(\.id), [b], "b leans the same small way as a; c leans the other way")
        // Without centring all three would score above 0.98 and all be suggested
        let plain = SuggestedIndex(vectors: [a: [10, 1, 0].map { $0 / 10.05 }, b: [10, 1.1, 0.1].map { $0 / 10.06 }, c: [10, -1, 0].map { $0 / 10.05 }])
        XCTAssertEqual(plain.suggestions(for: a).count, 2)
    }

    func testASingleNoteAndNoNotesBuildWithoutTroubleAndTrivialNotesAreLeftOut() {
        XCTAssertTrue(SuggestedIndex(sums: [:]).suggestions(for: UUID()).isEmpty)
        let only = UUID()
        XCTAssertTrue(SuggestedIndex(sums: [only: [1, 2, 3]]).suggestions(for: only).isEmpty)
        XCTAssertNil(SuggestedIndex.sum(title: "Untitled Note", body: "", using: toy))
    }

    func testExcludedNotesAndTheNoteItselfAreLeftOut() throws {
        let a = UUID(), b = UUID()
        let v = try XCTUnwrap(unit("dentist teeth"))
        let index = SuggestedIndex(vectors: [a: v, b: v])
        XCTAssertEqual(index.suggestions(for: a).map(\.id), [b])
        XCTAssertTrue(index.suggestions(for: a, excluding: [b]).isEmpty)
        XCTAssertTrue(index.suggestions(for: UUID()).isEmpty)
    }

    func testLimitAndTieOrderAreStable() throws {
        let ids = (0..<8).map { _ in UUID() }
        let v = try XCTUnwrap(unit("dentist dentist"))
        let dates = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, Date(timeIntervalSince1970: Double($0))) })
        let index = SuggestedIndex(vectors: Dictionary(uniqueKeysWithValues: ids.map { ($0, v) }), updated: dates)
        let top = index.suggestions(for: ids[0], limit: 3)
        XCTAssertEqual(top.map(\.id), [ids[7], ids[6], ids[5]], "equal similarity: newest first")
    }

    func testTheNoteTextUsedLeavesOutDateMarkers() {
        let note = Note(title: "Plan", content: "buy stamps 📅 2026-11-06")
        XCTAssertFalse(SuggestedIndex.text(of: note).contains("2026"))
    }

    /// Needs the English word model on this Mac; skipped where it is not installed
    func testAppleModelPutsSimilarNotesCloserThanUnrelatedOnes() throws {
        #if canImport(NaturalLanguage)
        let words = try XCTUnwrap(AppleWordVectors(), "no word model on this Mac")
        let dentist = try XCTUnwrap(SuggestedIndex.vector(for: "call the dentist tomorrow", using: words))
        let teeth = try XCTUnwrap(SuggestedIndex.vector(for: "teeth appointment on friday", using: words))
        let tax = try XCTUnwrap(SuggestedIndex.vector(for: "file the tax return", using: words))
        func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
        XCTAssertGreaterThan(dot(dentist, teeth), dot(dentist, tax))
        XCTAssertGreaterThanOrEqual(dot(dentist, teeth), SuggestedIndex.minimumScore)
        #else
        throw XCTSkip("no NaturalLanguage")
        #endif
    }
}
