import Foundation
import Carbon
import AppKit
import SwiftUI

/// A key plus modifiers that can be registered as a global hot key and shown in menus and settings.
public struct HotKeyShortcut: Codable, Equatable, Hashable, Sendable {
    /// Virtual key code, e.g. `kVK_ANSI_N`
    public var keyCode: UInt32
    /// Carbon modifier mask: `cmdKey`, `optionKey`, `controlKey`, `shiftKey`
    public var carbonModifiers: UInt32
    /// The key's character without modifiers, lowercased; empty for non-printing keys
    public var character: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, character: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.character = character
    }

    public static let quickCaptureDefault = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: UInt32(optionKey), character: "n")
    public static let searchDefault = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_F), carbonModifiers: UInt32(optionKey), character: "f")

    /// Builds a shortcut from a key press, or nil when it has no ⌘, ⌥ or ⌃ (a bare letter or ⇧+letter cannot be global).
    public init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        guard carbon != 0 else { return nil }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }

        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let printable = character.count == 1 && character.unicodeScalars.allSatisfy { $0.value > 32 && $0.value < 0xF700 }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbon, character: printable ? character : "")
    }

    private static let keyNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    /// Symbols in the order macOS shows them, e.g. "⌥N" or "⌃⌥⌘K".
    public var displayString: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        text += Self.keyNames[Int(keyCode)] ?? character.uppercased()
        return text
    }

    /// For menu items; nil for keys without a printable character.
    public var keyEquivalent: KeyEquivalent? {
        character.count == 1 ? KeyEquivalent(Character(character)) : nil
    }

    public var eventModifiers: SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if carbonModifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        return modifiers
    }

    /// True when the shortcut types a character if it is not intercepted, i.e. it uses ⌥ or ⇧ without ⌘ or ⌃.
    public var typesACharacter: Bool {
        carbonModifiers & UInt32(cmdKey | controlKey) == 0
    }
}
