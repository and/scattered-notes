import Foundation

/// The notes folder, either the app's own folder (visible in the Files app) or one the user picked in
/// Files, such as an iCloud Drive folder the Mac app also uses. iOS grants access to a folder outside
/// the app only through a security-scoped bookmark, so the bookmark is saved and access restarted at
/// every launch.
@MainActor
enum NotesFolder {
    private static let bookmarkKey = "settings.notesFolderBookmark"
    private static var accessedURL: URL?

    static var isCustom: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// Reopens the picked folder, or falls back to the app's own folder if it is gone or no longer allowed.
    static func restore(settings: AppSettings = .shared) {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            settings.notesDirectoryURL = AppSettings.defaultNotesDirectoryURL
            return
        }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else {
            useDefault(settings: settings)
            return
        }
        accessedURL = url
        if isStale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        settings.notesDirectoryURL = url
    }

    /// Switches to a folder picked in Files. Returns false when iOS does not grant access to it.
    @discardableResult
    static func use(_ url: URL, settings: AppSettings = .shared) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        guard let data = try? url.bookmarkData() else {
            url.stopAccessingSecurityScopedResource()
            return false
        }
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = url
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        settings.notesDirectoryURL = url
        return true
    }

    static func useDefault(settings: AppSettings = .shared) {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        settings.notesDirectoryURL = AppSettings.defaultNotesDirectoryURL
    }

    /// Reloads the notes. iCloud Drive keeps files that were never opened on this device as
    /// placeholders, which the storage manager does not see, so this asks for them to be downloaded
    /// and reloads again once they have had time to arrive.
    static func refresh(storage: NoteStorageManager = .shared) {
        storage.loadAll()
        guard downloadPlaceholders(in: storage.rootURL) else { return }
        Task {
            for delay in [2, 6] {
                try? await Task.sleep(for: .seconds(delay))
                storage.loadAll()
            }
        }
    }

    /// Returns whether any placeholder was found.
    private static func downloadPlaceholders(in root: URL) -> Bool {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return false }
        var found = false
        for case let file as URL in files {
            // A placeholder for "note.md" is named ".note.md.icloud"
            let name = file.lastPathComponent
            guard name.hasPrefix("."), name.hasSuffix(".md.icloud") else { continue }
            let real = file.deletingLastPathComponent()
                .appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
            try? FileManager.default.startDownloadingUbiquitousItem(at: real)
            found = true
        }
        return found
    }
}
