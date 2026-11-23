import XCTest
@testable import ScatteredNotes

/// A floated note gets one small window above other windows; floating it again reuses the window.
@MainActor
final class FloatingNoteTests: XCTestCase {
    func testFloatingOpensOneWindowAboveOthersAndClosing() throws {
        let note = Note(title: "Call notes", content: "")
        FloatingNotePanel.present(note: note)
        FloatingNotePanel.present(note: note)
        XCTAssertTrue(FloatingNotePanel.isFloating(note.id))

        let panels = NSApp.windows.compactMap { $0 as? FloatingNotePanel }
        XCTAssertEqual(panels.count, 1)
        let panel = try XCTUnwrap(panels.first)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertEqual(panel.title, "Call notes")

        panel.close()
        XCTAssertFalse(FloatingNotePanel.isFloating(note.id))
    }

    func testOpacityIsSharedClampedAndApplied() throws {
        let saved = FloatingNotePanel.opacity
        defer { FloatingNotePanel.opacity = saved }
        let note = Note(title: "Opacity", content: "")
        FloatingNotePanel.present(note: note)
        let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? FloatingNotePanel }.first { $0.title == "Opacity" })
        defer { panel.close() }

        FloatingNotePanel.opacity = 0.6
        XCTAssertEqual(panel.alphaValue, 0.6, accuracy: 0.001)
        FloatingNotePanel.opacity = 0
        XCTAssertEqual(FloatingNotePanel.opacity, FloatingNotePanel.minimumOpacity, accuracy: 0.001)
        FloatingNotePanel.opacity = 5
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
    }
}
