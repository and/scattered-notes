import Foundation

/// The history of date changes, kept as JSON Lines: one `DateChange` per line, only ever appended.
///
/// Each device appends to its own file, `.date-log-<device>.jsonl`, in the notes folder. iCloud then never
/// sees two devices change one file, so it never makes a conflict copy. Reading takes every device's file,
/// drops repeated ids and sorts by time, so the same history comes out on every device.
public final class DateChangeLog {
    public let directory: URL
    private let device: String
    private let fileManager = FileManager.default
    /// Changes by note, oldest first
    private var byNote: [UUID: [DateChange]] = [:]

    private static let prefix = ".date-log-"
    private static let suffix = ".jsonl"

    public init(directory: URL, device: String) {
        self.directory = directory
        self.device = device
        reload()
    }

    private var ownFile: URL {
        directory.appendingPathComponent(Self.prefix + device + Self.suffix)
    }

    /// Whether a file name is one of the log files, so note scans can leave it alone
    public static func isLogFile(_ name: String) -> Bool {
        name.hasPrefix(prefix) && name.hasSuffix(suffix)
    }

    /// The changes of one line of one note, oldest first
    public func history(noteID: UUID, lineText: String) -> [DateChange] {
        (byNote[noteID] ?? []).filter { $0.lineText == lineText }
    }

    /// Adds a change to this device's file and to the history in memory
    public func append(_ change: DateChange, write: (URL, (URL) throws -> Void) throws -> Void) throws {
        var line = try Self.encoder.encode(change)
        line.append(0x0A)
        try write(ownFile) { url in
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url, options: .atomic)
            }
        }
        byNote[change.noteID, default: []].append(change)
    }

    /// Reads every device's file again
    public func reload() {
        var seen = Set<UUID>()
        var all: [DateChange] = []
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where Self.isLogFile(file.lastPathComponent) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                // A line cut short by a crash or a half-finished sync fails to decode and is skipped
                guard let data = line.data(using: .utf8),
                      let change = try? Self.decoder.decode(DateChange.self, from: data),
                      seen.insert(change.id).inserted else { continue }
                all.append(change)
            }
        }
        all.sort { $0.at < $1.at }
        byNote = Dictionary(grouping: all, by: \.noteID)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
