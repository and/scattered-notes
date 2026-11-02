import SwiftUI

@main
struct ScatteredNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var storageManager = NoteStorageManager.shared
    @ObservedObject private var settings = AppSettings.shared
    /// The open window's New Note action, set by its note list
    @FocusedValue(\.newNoteAction) private var newNote
    @Environment(\.openWindow) private var openWindow

    init() {
        UITesting.prepare(AppSettings.shared)
    }
    
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
            // SwiftUI's own New Window item takes ⌘N and beats a button's shortcut, so a note
            // made with ⌘N skipped the open project. New Note takes ⌘N; New Window moves to ⇧⌘N.
            CommandGroup(replacing: .newItem) {
                Button("New Note") { newNote?() }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(newNote == nil)
                Button("New Window") { openWindow(id: "main") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                ShortcutMenuButton("Quick Capture...", shortcut: settings.quickCaptureShortcut) {
                    QuickCapturePanel.shared.showPanel()
                }
                ShortcutMenuButton("Search All Notes...", shortcut: settings.searchShortcut) {
                    AppRouter.showSearch()
                }
                Button("Go to Project, Person or Tag…") { AppRouter.showGoTo() }
                    .keyboardShortcut("o", modifiers: [.command])
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
