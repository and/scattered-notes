import CoreServices
import Foundation

/// Calls `onChange` on the main queue when anything inside a folder changes, including files in
/// subfolders. Uses FSEvents, which reports edits made by other apps and by sync clients (iCloud,
/// OneDrive) as well as files added, removed or renamed. Bursts of events are coalesced by `latency`.
// Only touched on the main queue: created and stopped by the storage manager, called back by FSEvents there
final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void
    /// The folder as given and as FSEvents reports it (symlinks resolved, e.g. /var is /private/var)
    private let rootPaths: [String]

    /// Whether a changed path is inside a hidden folder or is a hidden file, such as `.obsidian` or
    /// `.git`, which change often and hold no notes
    static func isHidden(_ path: String, below root: String) -> Bool {
        let base = root.hasSuffix("/") ? String(root.dropLast()) : root
        guard path.hasPrefix(base + "/") else { return false }
        return path.dropFirst(base.count).split(separator: "/").contains { $0.hasPrefix(".") }
    }

    private func isHidden(_ path: String) -> Bool {
        rootPaths.contains { Self.isHidden(path, below: $0) }
    }

    init?(url: URL, latency: TimeInterval = 0.3, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let resolved = url.resolvingSymlinksInPath().path
        self.rootPaths = resolved == url.path ? [url.path] : [url.path, resolved]
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            if count > 0, !changed.isEmpty, changed.allSatisfy({ watcher.isHidden($0) }) { return }
            // The stream is scheduled on the main queue, so this runs on the main thread
            MainActor.assumeIsolated { watcher.onChange() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
