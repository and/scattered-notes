import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire up global hotkey to toggle Quick Capture HUD
        GlobalHotKeyManager.shared.onHotKeyPressed = {
            QuickCapturePanel.shared.toggle()
        }
        GlobalHotKeyManager.shared.registerDefaultHotKey()
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where !(window is QuickCapturePanel) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
