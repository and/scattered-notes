import XCTest
import Carbon
@testable import ScatteredNotes

final class HotKeyShortcutTests: XCTestCase {
    func testDefaultsAreOptionNAndOptionF() {
        XCTAssertEqual(HotKeyShortcut.quickCaptureDefault.displayString, "⌥N")
        XCTAssertEqual(HotKeyShortcut.searchDefault.displayString, "⌥F")
        XCTAssertEqual(HotKeyShortcut.searchDefault.keyCode, UInt32(kVK_ANSI_F))
    }

    func testDisplayStringOrdersModifiersLikeMacOS() {
        let all = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey), character: "k")
        XCTAssertEqual(all.displayString, "⌃⌥⇧⌘K")
        let space = HotKeyShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey | cmdKey), character: "")
        XCTAssertEqual(space.displayString, "⌥⌘Space")
        XCTAssertNil(space.keyEquivalent)
    }

    func testOnlyOptionOrShiftShortcutsTypeACharacter() {
        XCTAssertTrue(HotKeyShortcut.searchDefault.typesACharacter)
        let withCommand = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_F), carbonModifiers: UInt32(optionKey | cmdKey), character: "f")
        XCTAssertFalse(withCommand.typesACharacter)
    }

    @MainActor
    func testShortcutsPersistAndFallBackToDefaults() {
        let suite = "com.scatterednotes.app.tests.hotkeys.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let settings = AppSettings(notesDirectoryURL: FileManager.default.temporaryDirectory, defaults: defaults)
        XCTAssertEqual(settings.quickCaptureShortcut, .quickCaptureDefault)
        XCTAssertEqual(settings.searchShortcut, .searchDefault)

        let custom = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: UInt32(cmdKey | shiftKey), character: "j")
        settings.searchShortcut = custom

        let reloaded = AppSettings(notesDirectoryURL: FileManager.default.temporaryDirectory, defaults: defaults)
        XCTAssertEqual(reloaded.searchShortcut, custom)
        XCTAssertEqual(reloaded.quickCaptureShortcut, .quickCaptureDefault)

        defaults.set(Data("garbage".utf8), forKey: "settings.searchShortcut")
        XCTAssertEqual(AppSettings(notesDirectoryURL: FileManager.default.temporaryDirectory, defaults: defaults).searchShortcut, .searchDefault)
    }

    @MainActor
    func testRegisteringTheSameShortcutTwiceIsRejected() {
        let manager = GlobalHotKeyManager.shared
        let probe = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_Y), carbonModifiers: UInt32(cmdKey | optionKey | controlKey), character: "y")
        XCTAssertEqual(manager.register(.search, shortcut: probe), noErr)
        XCTAssertEqual(manager.register(.quickCapture, shortcut: probe), OSStatus(eventHotKeyExistsErr))
        XCTAssertNotNil(manager.failures[.quickCapture])
        manager.unregister(.search)
        manager.unregister(.quickCapture)
        XCTAssertTrue(manager.failures.isEmpty)
    }
}
