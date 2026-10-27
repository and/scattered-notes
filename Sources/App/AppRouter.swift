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
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) && $0.contentView != nil }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            // No window left: relaunching the bundle makes SwiftUI open a new one
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
        NotificationCenter.default.post(name: .showGlobalSearch, object: nil)
    }
}
