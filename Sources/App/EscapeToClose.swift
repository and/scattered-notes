import AppKit

extension Notification.Name {
    /// Esc was pressed in the main window; the object is that window
    static let escapeInMainWindow = Notification.Name("ScatteredNotes.escapeInMainWindow")
}

/// Esc steps out of the window that has focus:
/// - main window: back to the Dashboard, and from the Dashboard it hides the window
/// - Settings and Quick Capture: closes them
///
/// Left alone so Esc keeps its normal job there:
/// - sheets and popovers, which dismiss themselves
/// - a text field mid-composition (accents, IME), where Esc cancels the composition
/// - while a shortcut is being recorded in Settings
@MainActor
enum EscapeToClose {
    private static var monitor: Any?
    /// Set by the shortcut recorder while it is waiting for a key press
    static var isRecordingShortcut = false

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    /// Returns true when the event closed a window and should not be delivered further.
    private static func handle(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              !isRecordingShortcut,
              let window = event.window ?? NSApp.keyWindow,
              window.sheetParent == nil,
              window.attachedSheet == nil,
              window.styleMask.contains(.closable) || window is NSPanel
        else { return false }

        if let textView = window.firstResponder as? NSTextView, textView.hasMarkedText() { return false }

        if let panel = window as? QuickCapturePanel {
            panel.hidePanel()
            return true
        }
        // The menu bar popover and other system owned windows manage their own Esc
        guard window.canBecomeMain || window.isKeyWindow, window.styleMask.contains(.titled) else { return false }

        if isSettingsWindow(window) {
            window.performClose(nil)
        } else {
            NotificationCenter.default.post(name: .escapeInMainWindow, object: window)
        }
        return true
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        (window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false)
            || window.title.localizedCaseInsensitiveContains("settings")
    }
}
