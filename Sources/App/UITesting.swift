import Foundation

/// Set when the screen tests in `UITests` start the app. It then keeps notes in the folder the
/// tests give it and stays away from iCloud and update checks.
enum UITesting {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    /// The empty folder a test made for its notes
    static var notesFolder: URL? {
        ProcessInfo.processInfo.environment["SN_UITEST_NOTES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Points the settings at the test's folder and options, before anything reads them
    @MainActor
    static func prepare(_ settings: AppSettings) {
        guard isActive, let folder = notesFolder else { return }
        settings.notesDirectoryURL = folder
        settings.quickNoteAutoSave = !ProcessInfo.processInfo.arguments.contains("-manualQuickNote")
        UserDefaults.standard.removeObject(forKey: "dashboard.showCompleted")
        UserDefaults.standard.removeObject(forKey: "dashboard.completedExpanded")
    }
}
