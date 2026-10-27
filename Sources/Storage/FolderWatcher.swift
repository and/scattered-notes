import CoreServices
import Foundation

/// Calls `onChange` on the main queue when anything inside a folder changes, including files in
/// subfolders. Uses FSEvents, which reports edits made by other apps and by sync clients (iCloud,
/// OneDrive) as well as files added, removed or renamed. Bursts of events are coalesced by `latency`.
// Only touched on the main queue: created and stopped by the storage manager, called back by FSEvents there
final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    init?(url: URL, latency: TimeInterval = 0.3, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            // The stream is scheduled on the main queue, so this runs on the main thread
            MainActor.assumeIsolated { watcher.onChange() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
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
