import AppKit
import Combine

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    public func applicationDidFinishLaunching(_ notification: Notification) {
        EscapeToClose.install()
        UpdateChecker.shared.start()
        Task { await StorageFolderPicker.offerICloudIfNeeded() }
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
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainActor.assumeIsolated { AppRouter.showMainWindow() }
        }
        return true
    }
}
