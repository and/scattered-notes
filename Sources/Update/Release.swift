import Foundation

/// A version such as "1.1.1", compared number by number. Tags may start with "v".
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        // Pre-release suffixes such as "-beta" are not offered as updates
        guard !trimmed.isEmpty, !trimmed.contains("-") else { return nil }
        let numbers = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        parts = numbers.map { $0! }
    }

    /// The running app's version, from CFBundleShortVersionString.
    public static var current: AppVersion {
        AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") ?? AppVersion("0")!
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    public var description: String { parts.map(String.init).joined(separator: ".") }
}

/// A published GitHub release, as returned by the releases API.
public struct Release: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        public let size: Int
        public let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    public let tagName: String
    public let name: String?
    /// The release notes, in Markdown
    public let body: String?
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, draft, prerelease, assets
        case htmlURL = "html_url"
    }

    public var version: AppVersion? { AppVersion(tagName) }

    /// The Mac download, named `ScatteredNotes-<version>-mac.zip`.
    public var macAsset: Asset? { assets.first { $0.name.lowercased().hasSuffix("-mac.zip") } }

    /// The release notes without the download table, which only matters on the website.
    public var notes: String {
        let lines = (body ?? "").replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether this release should be offered to an app running `installed`, unless the user skipped it.
    public func isUpdate(over installed: AppVersion, skipped: String?) -> Bool {
        guard !draft, !prerelease, let version, version > installed, macAsset != nil else { return false }
        return skipped.flatMap(AppVersion.init).map { $0 != version } ?? true
    }
}
