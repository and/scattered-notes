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
        XCTAssertNil(unit(""))
        XCTAssertNil(unit("the and for"), "stop words carry nothing")
    }

    func testShortWordsAndNumbersAreIgnored() throws {
        let plain = try XCTUnwrap(unit("dentist"))
        let padded = try XCTUnwrap(unit("dentist 2026 at of 12345"))
        XCTAssertEqual(plain, padded)
    }

    func testNotesCloseInMeaningAreSuggestedAndFarOnesAreNot() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let index = SuggestedIndex(vectors: [a: try XCTUnwrap(unit("dentist")), b: try XCTUnwrap(unit("teeth appointment")), c: try XCTUnwrap(unit("taxes invoice"))])
        let result = index.suggestions(for: a)
        XCTAssertEqual(result.map(\.id), [b])
        XCTAssertGreaterThan(result[0].similarity, SuggestedIndex.minimumSimilarity)
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
        let v = try XCTUnwrap(unit("dentist"))
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
        XCTAssertGreaterThanOrEqual(dot(dentist, teeth), SuggestedIndex.minimumSimilarity)
        #else
        throw XCTSkip("no NaturalLanguage")
        #endif
    }
}
