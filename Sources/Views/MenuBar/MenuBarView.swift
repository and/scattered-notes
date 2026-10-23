import SwiftUI

public struct MenuBarView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    @Environment(\.openWindow) private var openWindow
    
    public init() {}
    
    public var body: some View {
        VStack {
            Button(action: {
                QuickCapturePanel.shared.showPanel()
            }) {
                Label("Quick Capture...", systemImage: "bolt.fill")
            }
            .keyboardShortcut("n", modifiers: [.option])
            
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where !(window is QuickCapturePanel) {
                    window.makeKeyAndOrderFront(nil)
                }
            }) {
                Label("Open Scattered Notes", systemImage: "macwindow")
            }
            
            Divider()
            
            if !storageManager.notes.isEmpty {
                Section("Recent Notes") {
                    ForEach(storageManager.notes.prefix(5)) { note in
                        Button(action: {
                            NSApp.activate(ignoringOtherApps: true)
                            for window in NSApp.windows where !(window is QuickCapturePanel) {
                                window.makeKeyAndOrderFront(nil)
                            }
                        }) {
                            HStack {
                                Image(systemName: note.categoryType.iconName)
                                Text(note.displayTitle)
                            }
                        }
                    }
                }
                Divider()
            }
            
            Button(action: {
                NSWorkspace.shared.open(storageManager.rootURL)
            }) {
                Label("Open Storage Folder", systemImage: "folder")
            }
            
            Divider()
            
            Button("Quit Scattered Notes") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
