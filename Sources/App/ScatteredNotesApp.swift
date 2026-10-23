import SwiftUI

@main
struct ScatteredNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var storageManager = NoteStorageManager.shared
    
    var body: some Scene {
        WindowGroup("Scattered Notes", id: "main") {
            MainSplitView()
                .frame(minWidth: 800, minHeight: 520)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("Quick Capture...") {
                    QuickCapturePanel.shared.showPanel()
                }
                .keyboardShortcut("n", modifiers: [.option])
            }
        }
        
        MenuBarExtra("Scattered Notes", systemImage: "note.text.badge.plus") {
            MenuBarView()
        }
    }
}
