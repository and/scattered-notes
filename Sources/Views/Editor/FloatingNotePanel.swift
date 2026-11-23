import AppKit
import SwiftUI

/// A note in a small window of its own that stays above other windows, so it can sit beside a browser while
/// you take notes. One window for each note: floating a note that already floats brings its window forward.
/// The window shows the title and the text only; its pin-style button puts the note back.
final class FloatingNotePanel: NSPanel {
    private static var open: [UUID: FloatingNotePanel] = [:]
    private static let frameKey = "FloatingNotePanelFrame"
    private static let minimumSize = NSSize(width: 220, height: 140)

    private let noteID: UUID

    static func isFloating(_ id: UUID) -> Bool { open[id] != nil }

    /// How solid the floating windows are, from `minimumOpacity` to 1. One setting for all of them, kept between launches.
    static let minimumOpacity = 0.3
    private static let opacityKey = "FloatingNoteOpacity"

    static var opacity: Double {
        get {
            let saved = UserDefaults.standard.object(forKey: opacityKey) as? Double ?? 1
            return min(1, max(minimumOpacity, saved))
        }
        set {
            let value = min(1, max(minimumOpacity, newValue))
            UserDefaults.standard.set(value, forKey: opacityKey)
            for panel in open.values { panel.alphaValue = value }
        }
    }

    static func present(note: Note) {
        if let existing = open[note.id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let panel = FloatingNotePanel(note: note)
        panel.place(besides: open.values.first { $0.isVisible })
        open[note.id] = panel
        // The header's float button shows it blue while a note floats
        NotificationCenter.default.post(name: .floatingNotesChanged, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private init(note: Note) {
        noteID = note.id
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 440),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        title = note.displayTitle
        isFloatingPanel = true
        level = .floating
        // Stays where it is when the app is not in front, and follows to other desktops
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        alphaValue = Self.opacity
        contentMinSize = Self.minimumSize

        let host = NSHostingView(rootView: NoteDetailEditorView(note: note, isFloating: true, onUnfloat: { [weak self] in
            // Closing takes the editor out of the window; do it after the button's action has returned
            DispatchQueue.main.async { self?.close() }
        }))
        host.sizingOptions = []
        contentView = host

        if let saved = UserDefaults.standard.string(forKey: Self.frameKey) {
            let rect = NSRectFromString(saved)
            if rect.width >= Self.minimumSize.width, rect.height >= Self.minimumSize.height,
               NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                setFrame(rect, display: false)
                hasSavedFrame = true
            }
        }
        frameObservers = [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rememberFrame() }
            }
        }
    }

    private var hasSavedFrame = false
    /// Removed on close, so a closed window leaves no observers behind
    private var frameObservers: [NSObjectProtocol] = []

    private func rememberFrame() {
        guard isVisible else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    private func place(besides other: FloatingNotePanel?) {
        if let other {
            setFrameOrigin(NSPoint(x: other.frame.minX + 28, y: other.frame.minY - 28))
        } else if !hasSavedFrame, let screen = NSScreen.main {
            // First time: the right edge of the screen, where a browser leaves room
            let area = screen.visibleFrame
            setFrameOrigin(NSPoint(x: area.maxX - frame.width - 24, y: area.maxY - frame.height - 24))
        }
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        rememberFrame()
        frameObservers.forEach(NotificationCenter.default.removeObserver)
        frameObservers = []
        // Taking the editor out of the window lets it save what was typed last
        contentView = NSView()
        Self.open[noteID] = nil
        super.close()
        NotificationCenter.default.post(name: .floatingNotesChanged, object: nil)
    }
}

extension Notification.Name {
    static let floatingNotesChanged = Notification.Name("ScatteredNotes.floatingNotesChanged")
}
