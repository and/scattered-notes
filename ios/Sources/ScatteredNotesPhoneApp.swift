import SwiftUI

@main
struct ScatteredNotesPhoneApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before the storage manager first reads the folder
        NotesFolder.restore()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS has no folder watcher, so pick up edits made on other devices when the app comes back
            if phase == .active { NotesFolder.refresh() }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            DashboardScreen()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            NotesScreen()
                .tabItem { Label("Notes", systemImage: "note.text") }
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
