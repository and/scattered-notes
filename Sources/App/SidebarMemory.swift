import AppKit

/// Remembers whether the project list (the first column) was hidden, and hides it again when a window opens.
/// The window's own split view is read, since SwiftUI's column setting does not follow the toolbar button or
/// dragging the divider. The state is saved when the window closes or the app quits, not while the window
/// lays itself out, because a new window starts with the list showing and would save over the choice.
@MainActor
final class SidebarMemory: NSObject {
    static let shared = SidebarMemory()
    private static let key = "sidebarHidden"

    private var observing = false
    /// Windows already set up, so coming back to one does not hide its sidebar again
    private let handled = NSHashTable<NSWindow>.weakObjects()

    /// Called when a main window becomes key. A window opened again after the red close button is a new one,
    /// so each gets the saved state.
    func restore(in window: NSWindow) {
        guard !UITesting.isActive else { return }
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                                                   name: NSWindow.willCloseNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(appWillTerminate(_:)),
                                                   name: NSApplication.willTerminateNotification, object: nil)
        }
        guard !handled.contains(window) else { return }
        handled.add(window)
        let wantHidden = UserDefaults.standard.bool(forKey: Self.key)
        // Once the window has been laid out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak window] in
            guard wantHidden, let window, let split = Self.splitView(in: window.contentView), !Self.isSidebarHidden(split) else { return }
            NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, handled.contains(window) else { return }
        save(from: window)
    }

    @objc private func appWillTerminate(_ notification: Notification) {
        if let window = handled.allObjects.first(where: { $0.isVisible }) { save(from: window) }
    }

    private func save(from window: NSWindow) {
        guard let split = Self.splitView(in: window.contentView), split.bounds.width > 0 else { return }
        UserDefaults.standard.set(Self.isSidebarHidden(split), forKey: Self.key)
    }

    private static func isMainSplitView(_ split: NSSplitView) -> Bool {
        split.autosaveName?.hasSuffix("SidebarNavigationSplitView") ?? false
    }

    private static func isSidebarHidden(_ split: NSSplitView) -> Bool {
        guard let first = split.arrangedSubviews.first else { return false }
        return split.isSubviewCollapsed(first) || first.isHidden || first.frame.width < 1
    }

    private static func splitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let split = view as? NSSplitView, isMainSplitView(split) { return split }
        for subview in view.subviews {
            if let found = splitView(in: subview) { return found }
        }
        return nil
    }
}
