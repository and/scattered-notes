import SwiftUI
import UserNotifications

@main
struct ScatteredNotesPhoneApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        MorningReminder.registerBackgroundRefresh()
        // Screen tests run on an empty folder of their own, never on real notes
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            AppSettings.shared.notesDirectoryURL = folder
            return
        }
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
            // The morning summaries are prepared from the notes as they are when the app is left
            if phase == .background { Task { await MorningReminder.reschedule() } }
        }
    }
}

struct RootView: View {
    enum Tab { case dashboard, notes, settings }
    @State private var tab = Tab.dashboard

    var body: some View {
        TabView(selection: $tab) {
            DashboardScreen()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
                .tag(Tab.dashboard)
            NotesScreen()
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(Tab.notes)
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        // A tapped morning summary opens the Dashboard
        .onReceive(NotificationCenter.default.publisher(for: NotificationRouter.openDashboard)) { _ in tab = .dashboard }
    }
}
