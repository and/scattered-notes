import XCTest
@testable import ScatteredNotes

final class CursorMemoryTests: XCTestCase {
    func testEachNoteKeepsItsOwnPlace() {
        var memory = CursorMemory()
        let a = UUID(), b = UUID()
        memory.remember(12, for: a)
        memory.remember(40, for: b)
        XCTAssertEqual(memory.offset(for: a), 12)
        XCTAssertEqual(memory.offset(for: b), 40)
        XCTAssertNil(memory.offset(for: UUID()))
        memory.remember(3, for: a)
        XCTAssertEqual(memory.offset(for: a), 3)
        XCTAssertEqual(memory.count, 2)
    }

    func testOnlyTheMostRecentNotesAreKept() {
        var memory = CursorMemory()
        let first = UUID()
        memory.remember(1, for: first)
        for _ in 0..<CursorMemory.limit { memory.remember(5, for: UUID()) }
        XCTAssertEqual(memory.count, CursorMemory.limit)
        XCTAssertNil(memory.offset(for: first))
    }

    func testSurvivesBeingSavedAndRead() throws {
        var memory = CursorMemory()
        let id = UUID()
        memory.remember(77, for: id)
        let decoded = try JSONDecoder().decode(CursorMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(decoded.offset(for: id), 77)
    }

    func testForgetting() {
        var memory = CursorMemory()
        let id = UUID()
        memory.remember(9, for: id)
        memory.forget(id)
        XCTAssertNil(memory.offset(for: id))
        XCTAssertEqual(memory.count, 0)
    }
}
