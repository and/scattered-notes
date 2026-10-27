import AppKit
import Foundation
import Security

/// Looks for a newer release on GitHub, shows what is in it, and installs it when the user agrees.
///
/// Checks run at launch and once a day when "Check for updates automatically" is on, and whenever the
/// user picks "Check for Updates…". Nothing is downloaded until the user clicks Install. The download
/// must be signed by the same Developer ID team as this app, or it is thrown away.
@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    public static let releasesAPI = URL(string: "https://api.github.com/repos/and/scattered-notes/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/and/scattered-notes/releases/latest")!
    /// The Developer ID team that signs every release
    nonisolated static let teamID = "RLVYQT69D4"

    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading
        case installing
        case failed(String)
    }

    @Published public private(set) var state: State = .idle

    @Published public var automaticallyChecks: Bool {
        didSet { defaults.set(automaticallyChecks, forKey: Keys.automatic) }
    }

    public var lastCheck: Date? { defaults.object(forKey: Keys.lastCheck) as? Date }

    private enum Keys {
        static let automatic = "updates.automaticallyChecks"
        static let lastCheck = "updates.lastCheck"
        static let skipped = "updates.skippedVersion"
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private var timer: Timer?

    public init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        automaticallyChecks = defaults.object(forKey: Keys.automatic) as? Bool ?? true
    }

    /// Call once at launch: checks now if a day has passed, then keeps checking daily.
    public func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task { @MainActor in UpdateChecker.shared.checkIfDue() }
        }
        // Give the app a moment to open its windows first
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.checkIfDue() }
    }

    func checkIfDue() {
        guard automaticallyChecks, case .idle = state else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 20 * 60 * 60 { return }
        Task { await check(userInitiated: false) }
    }

    /// Fetches the latest release. A user-initiated check also reports "up to date" and errors, and
    /// ignores a previously skipped version.
    public func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .checking
        do {
            var request = URLRequest(url: Self.releasesAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("ScatteredNotes/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.server }
            let release = try JSONDecoder().decode(Release.self, from: data)
            defaults.set(Date(), forKey: Keys.lastCheck)

            let skipped = userInitiated ? nil : defaults.string(forKey: Keys.skipped)
            if release.isUpdate(over: .current, skipped: skipped) {
                state = .available(release)
                UpdateWindow.show()
            } else {
                state = userInitiated ? .upToDate : .idle
                if userInitiated { UpdateWindow.show() }
            }
        } catch {
            state = userInitiated ? .failed("Couldn't check for updates. Check your internet connection and try again.") : .idle
            if userInitiated { UpdateWindow.show() }
        }
    }

    /// Stops offering this version; a later one is still offered.
    public func skip(_ release: Release) {
        defaults.set(release.tagName, forKey: Keys.skipped)
        state = .idle
    }

    public func remindLater() {
        state = .idle
    }

    /// Whether the app can replace itself: it must sit in a folder the user can write to.
    public var canInstallInPlace: Bool {
        let bundle = Bundle.main.bundleURL
        return bundle.pathExtension == "app" &&
            FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
    }

    /// Downloads the release, checks its signature, swaps it in for this copy of the app and relaunches.
    public func install(_ release: Release) async {
        guard let asset = release.macAsset else { return }
        guard canInstallInPlace else {
            NSWorkspace.shared.open(release.htmlURL)
            state = .idle
            return
        }
        state = .downloading
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("ScatteredNotesUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent(asset.name)
            try await download(asset.browserDownloadURL, to: zip, expectedSize: asset.size)

            state = .installing
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else { throw UpdateError.badArchive }
            try Self.verifySignature(of: newApp)
            try relaunch(replacing: Bundle.main.bundleURL, with: newApp)
        } catch let error as UpdateError {
            state = .failed(error.message)
        } catch {
            state = .failed("The update couldn't be installed: \(error.localizedDescription)")
        }
    }

    private func download(_ url: URL, to destination: URL, expectedSize: Int) async throws {
        let (file, response) = try await session.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.server }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? -1
        guard size == expectedSize else { throw UpdateError.badArchive }
        try FileManager.default.moveItem(at: file, to: destination)
    }

    /// Accepts only an app signed by our Developer ID team with our bundle identifier.
    nonisolated static func verifySignature(of app: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw UpdateError.unsigned }
        let requirementText = "identifier \"com.scatterednotes.app\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess else { throw UpdateError.unsigned }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { throw UpdateError.unsigned }
    }

    /// A small script waits for this app to quit (so pending edits are saved), swaps the bundles, keeps
    /// the old one if anything fails, and opens the new version.
    private func relaunch(replacing current: URL, with newApp: URL) throws {
        let backup = newApp.deletingLastPathComponent().appendingPathComponent("previous.app")
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        if mv "$CURRENT" "$BACKUP" && mv "$NEW" "$CURRENT"; then
            open "$CURRENT"
        else
            [ -d "$BACKUP" ] && [ ! -d "$CURRENT" ] && mv "$BACKUP" "$CURRENT"
            open "$CURRENT"
        fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.environment = ["CURRENT": current.path, "NEW": newApp.path, "BACKUP": backup.path, "PATH": "/usr/bin:/bin"]
        try process.run()
        NSApp.terminate(nil)
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.badArchive }
    }
}

enum UpdateError: Error {
    case server
    case badArchive
    case unsigned

    var message: String {
        switch self {
        case .server: return "GitHub didn't send the update. Try again later."
        case .badArchive: return "The download was incomplete or damaged. Try again."
        case .unsigned: return "The download isn't signed by Scattered Notes, so it wasn't installed."
        }
    }
}
