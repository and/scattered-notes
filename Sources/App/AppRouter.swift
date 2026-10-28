import AppKit

extension Notification.Name {
    static let showGlobalSearch = Notification.Name("ScatteredNotes.showGlobalSearch")
}

/// Brings the main window forward for actions triggered from outside it, such as a global hot key.
@MainActor
enum AppRouter {
    /// Set when search was requested before the main window could listen for it
    static var pendingSearch = false

    static func showSearch() {
        pendingSearch = true
        showMainWindow()
        NotificationCenter.default.post(name: .showGlobalSearch, object: nil)
    }

    /// Brings only the main window forward. Ordering every window in `NSApp.windows` front also
    /// re-shows AppKit's own helper windows, such as the menu bar menu as it fades out, which then
    /// sit on screen invisible and swallow clicks on that part of the screen.
    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: {
            $0.canBecomeMain && !($0 is NSPanel) && $0.level == .normal && $0.contentView != nil
        }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            // No window left: relaunching the bundle makes SwiftUI open a new one
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
    }
}
