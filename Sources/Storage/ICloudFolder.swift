import Foundation

/// The app's own folder in iCloud Drive, shown as "Scattered Notes" in Finder, the Files app and
/// iCloud.com. The Mac and iPhone apps share it, so notes kept there sync without picking a folder on
/// each device. Only signed release builds carry the iCloud entitlement; elsewhere `locate()` returns nil.
public enum ICloudFolder {
    public static let containerID = "iCloud.com.scatterednotes"

    /// Whether this device is signed in to iCloud with iCloud Drive on. Cheap enough for the main thread.
    public static var isSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// The notes folder inside the container, or nil when iCloud Drive is off or the app has no
    /// iCloud entitlement. Looking up the container can take a while the first time, so it runs off
    /// the main thread.
    public static func locate() async -> URL? {
        guard isSignedIn else { return nil }
        return await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: containerID)?
                .appendingPathComponent("Documents", isDirectory: true)
        }.value
    }

    /// Whether `url` is inside the app's iCloud container. iCloud names the container folder after
    /// the identifier with dots swapped for tildes, on the Mac and on iOS.
    public static func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains(containerID.replacingOccurrences(of: ".", with: "~"))
    }

    /// Asks iCloud to download notes it keeps only as placeholders ("note.md" appears as
    /// ".note.md.icloud" until downloaded). Returns whether any were found.
    @discardableResult
    public static func downloadPlaceholders(in root: URL) -> Bool {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return false }
        var found = false
        for case let file as URL in files {
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

/// Follows the notes in the app's iCloud container through iCloud's own index. Calls `onChange` when
/// a note arrives, changes or is removed on another device, and downloads notes that are only in
/// the cloud (new ones from other devices, or ones the Mac removed to save space), so every note
/// is readable on this device.
@MainActor
final class ICloudWatcher {
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.md'", NSMetadataItemFSNameKey)
        query.notificationBatchingInterval = 0.5
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.downloadMissing()
                    onChange()
                }
            })
        }
        query.start()
    }

    private func downloadMissing() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
                    == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded else { continue }
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    func stop() {
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}
