import AppKit
import Combine

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    public func applicationDidFinishLaunching(_ notification: Notification) {
        EscapeToClose.install()
        // Remember the size and place of the main window, so it opens as it was left
        NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey(_:)),
                                               name: NSWindow.didBecomeKeyNotification, object: nil)
        EditorFocus.installPlaceTracking()
        EditorFocus.installLeftArrowExit()
        if !UITesting.isActive {
            UpdateChecker.shared.start()
            Task { await StorageFolderPicker.offerICloudIfNeeded() }
        }
        let hotKeys = GlobalHotKeyManager.shared
        let settings = AppSettings.shared

        hotKeys.setAction(.quickCapture) { QuickCapturePanel.shared.toggle() }
        hotKeys.setAction(.search) { AppRouter.showSearch() }

        // @Published emits on willSet, so hop to the next main-queue turn to read the new values
        Publishers.CombineLatest(settings.$quickCaptureShortcut, settings.$searchShortcut)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                hotKeys.register(.quickCapture, shortcut: settings.quickCaptureShortcut)
                hotKeys.register(.search, shortcut: settings.searchShortcut)
            }
            .store(in: &cancellables)
    }
    
    @MainActor @objc private func windowBecameKey(_ notification: Notification) {
        guard !UITesting.isActive, let window = notification.object as? NSWindow,
              window.canBecomeMain, !(window is NSPanel), window.level == .normal, window.contentView != nil,
              window.frameAutosaveName.isEmpty || window.frameAutosaveName == "ScatteredNotesMainWindow" else { return }
        // Fails for a second window, the name being taken, which then opens at the size of the first
        if window.frameAutosaveName.isEmpty { window.setFrameAutosaveName("ScatteredNotesMainWindow") }
        SidebarMemory.shared.restore(in: window)
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainActor.assumeIsolated { AppRouter.showMainWindow() }
        }
        return true
    }
}
