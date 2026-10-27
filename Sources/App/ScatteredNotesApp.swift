import SwiftUI

@main
struct ScatteredNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var storageManager = NoteStorageManager.shared
    @ObservedObject private var settings = AppSettings.shared
    
    var body: some Scene {
        WindowGroup("Scattered Notes", id: "main") {
            MainSplitView()
                .frame(minWidth: 800, minHeight: 520)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await UpdateChecker.shared.check(userInitiated: true) }
                }
            }
            CommandGroup(after: .newItem) {
                ShortcutMenuButton("Quick Capture...", shortcut: settings.quickCaptureShortcut) {
                    QuickCapturePanel.shared.showPanel()
                }
                ShortcutMenuButton("Search All Notes...", shortcut: settings.searchShortcut) {
                    AppRouter.showSearch()
                }
            }
        }
        
        Settings {
            SettingsView()
        }
        
        MenuBarExtra("Scattered Notes", systemImage: "note.text.badge.plus") {
            MenuBarView()
        }
    }
}

/// A menu button that shows the user's configured shortcut.
struct ShortcutMenuButton: View {
    let title: String
    let shortcut: HotKeyShortcut
    let action: () -> Void

    init(_ title: String, shortcut: HotKeyShortcut, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        if let key = shortcut.keyEquivalent {
            Button(title, action: action).keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            Button(title, action: action)
        }
    }
}
