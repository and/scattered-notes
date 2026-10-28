import Foundation

/// The notes folder: the app's own iCloud Drive folder (the default when signed in to iCloud, shared
/// with the Mac app), a folder the user picked in Files, or the app's folder on this device.
/// iOS grants access to a picked folder only through a security-scoped bookmark, so the bookmark is
/// saved and access restarted at every launch.
@MainActor
enum NotesFolder {
    enum Kind { case iCloud, picked, onDevice }

    private static let bookmarkKey = "settings.notesFolderBookmark"
    /// Set when the user chose the folder on this device over iCloud Drive
    private static let onDeviceKey = "settings.notesFolderOnDevice"
    private static var accessedURL: URL?

    static func kind(of url: URL) -> Kind {
        if ICloudFolder.contains(url) { return .iCloud }
        return UserDefaults.standard.data(forKey: bookmarkKey) != nil ? .picked : .onDevice
    }

    /// Reopens the folder used last. A picked folder that is gone or no longer allowed falls back to
    /// the folder on this device. iCloud Drive is used whenever the user hasn't chosen otherwise.
    static func restore(settings: AppSettings = .shared) {
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale),
                  url.startAccessingSecurityScopedResource() else {
                useOnDevice(settings: settings)
                return
            }
            accessedURL = url
            if isStale, let fresh = try? url.bookmarkData() {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
            settings.notesDirectoryURL = url
            return
        }
        // The container path doesn't change, so the last one is used at once and confirmed below
        guard !UserDefaults.standard.bool(forKey: onDeviceKey), ICloudFolder.isSignedIn else {
            settings.notesDirectoryURL = AppSettings.defaultNotesDirectoryURL
            return
        }
        if !ICloudFolder.contains(settings.notesDirectoryURL) {
            settings.notesDirectoryURL = AppSettings.defaultNotesDirectoryURL
        }
        // Runs after launch, once the storage manager exists
        Task { await useICloud(settings: settings) }
    }

    /// Switches to the app's iCloud Drive folder and moves any notes kept on this device into it.
    /// Notes in a picked folder stay there, since the Mac may still use that folder. Returns false
    /// when iCloud Drive isn't available.
    @discardableResult
    static func useICloud(settings: AppSettings = .shared, storage: NoteStorageManager = .shared) async -> Bool {
        guard let url = await ICloudFolder.locate() else {
            if ICloudFolder.contains(settings.notesDirectoryURL) {
                settings.notesDirectoryURL = AppSettings.defaultNotesDirectoryURL
            }
            return false
        }
        UserDefaults.standard.removeObject(forKey: onDeviceKey)
        if kind(of: settings.notesDirectoryURL) == .picked {
            stopAccessingPicked()
            settings.notesDirectoryURL = AppSettings.defaultNotesDirectoryURL
        }
        guard settings.notesDirectoryURL.standardizedFileURL != url.standardizedFileURL else { return true }
        _ = try? storage.relocateStorage(to: url)
        return true
    }

    /// Switches to a folder picked in Files. Returns false when iOS does not grant access to it.
    @discardableResult
    static func use(_ url: URL, settings: AppSettings = .shared) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        guard let data = try? url.bookmarkData() else {
            url.stopAccessingSecurityScopedResource()
            return false
        }
        stopAccessingPicked()
        accessedURL = url
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        settings.notesDirectoryURL = url
        return true
    }

    /// Switches to the app's folder on this device. Notes elsewhere are left where they are.
    static func useOnDevice(settings: AppSettings = .shared) {
        stopAccessingPicked()
        UserDefaults.standard.set(true, forKey: onDeviceKey)
        settings.notesDirectoryURL = AppSettings.defaultNotesDirectoryURL
    }

    private static func stopAccessingPicked() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Reloads the notes. iCloud Drive keeps files that were never opened on this device as
    /// placeholders, which the storage manager does not see, so this asks for them to be downloaded
    /// and reloads again once they have had time to arrive. In the app's iCloud folder the storage
    /// manager also follows iCloud's index and reloads as notes arrive.
    static func refresh(storage: NoteStorageManager = .shared) {
        storage.loadAll()
        guard ICloudFolder.downloadPlaceholders(in: storage.rootURL) else { return }
        Task {
            for delay in [2, 6] {
                try? await Task.sleep(for: .seconds(delay))
                storage.loadAll()
            }
        }
    }
}
