import SwiftUI
import AppKit

/// Shows a folder picker, then moves existing notes into the chosen folder.
@MainActor
public enum StorageFolderPicker {
    public static func chooseAndRelocate(storageManager: NoteStorageManager = .shared) {
        let panel = NSOpenPanel()
        panel.title = "Choose Notes Folder"
        panel.message = "Your existing notes will be moved into the selected folder."
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = storageManager.rootURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else { return }
        relocate(to: url, storageManager: storageManager)
    }

    public static func relocate(to url: URL, storageManager: NoteStorageManager = .shared) {
        let alert = NSAlert()
        do {
            let moved = try storageManager.relocateStorage(to: url)
            alert.messageText = "Notes Folder Changed"
            alert.informativeText = moved == 0
                ? "Notes are now stored in \(url.path)."
                : "Moved \(moved) note\(moved == 1 ? "" : "s") to \(url.path)."
        } catch {
            alert.alertStyle = .warning
            alert.messageText = "Couldn't Change Notes Folder"
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
    }

    /// Moves the notes into the app's own iCloud Drive folder, or explains why iCloud isn't available.
    public static func relocateToICloud(storageManager: NoteStorageManager = .shared) async {
        guard let url = await ICloudFolder.locate() else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "iCloud Drive Isn't Available"
            alert.informativeText = "Sign in to iCloud and turn on iCloud Drive in System Settings → Apple Account → iCloud, then try again."
            alert.runModal()
            return
        }
        relocate(to: url, storageManager: storageManager)
    }

    /// Once, on a Mac signed in to iCloud that still uses the default folder, offers to keep the notes in
    /// iCloud Drive so the iPhone and iPad app sees them. With no notes yet, it switches without asking.
    public static func offerICloudIfNeeded(
        storageManager: NoteStorageManager = .shared,
        settings: AppSettings = .shared,
        defaults: UserDefaults = .standard
    ) async {
        let offeredKey = "settings.iCloudOffered"
        guard !defaults.bool(forKey: offeredKey), !settings.hasChosenNotesFolder,
              let url = await ICloudFolder.locate() else { return }
        defaults.set(true, forKey: offeredKey)
        guard !storageManager.notes.isEmpty else {
            _ = try? storageManager.relocateStorage(to: url)
            return
        }

        let count = storageManager.notes.count
        let alert = NSAlert()
        alert.messageText = "Keep Your Notes in iCloud Drive?"
        alert.informativeText = "Scattered Notes can keep your \(count) note\(count == 1 ? "" : "s") in its own iCloud Drive folder, so they sync to your other Macs and the iPhone and iPad app. They stay plain Markdown files, in iCloud Drive → Scattered Notes. You can change this later in Settings → Notes Folder."
        alert.addButton(withTitle: "Move to iCloud Drive")
        alert.addButton(withTitle: "Keep on This Mac")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            relocate(to: url, storageManager: storageManager)
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var hotKeys = GlobalHotKeyManager.shared
    @ObservedObject var updates = UpdateChecker.shared

    public init() {}

    public var body: some View {
        Form {
            Section("Notes Folder") {
                Text(ICloudFolder.contains(settings.notesDirectoryURL) ? "iCloud Drive → Scattered Notes" : settings.notesDirectoryURL.path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack {
                    Button("Change…") {
                        StorageFolderPicker.chooseAndRelocate(storageManager: storageManager)
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.open(storageManager.rootURL)
                    }
                    Spacer()
                    Button("Use iCloud Drive") {
                        Task { await StorageFolderPicker.relocateToICloud(storageManager: storageManager) }
                    }
                    .disabled(ICloudFolder.contains(settings.notesDirectoryURL))
                    Button("Use Default") {
                        StorageFolderPicker.relocate(to: AppSettings.defaultNotesDirectoryURL, storageManager: storageManager)
                    }
                    .disabled(settings.notesDirectoryURL.standardizedFileURL == AppSettings.defaultNotesDirectoryURL.standardizedFileURL)
                }

                Text("Changing the folder moves all existing notes, projects and areas into it. iCloud Drive keeps them in sync with your other Macs and the iPhone and iPad app.")
                    .font(.caption)
                    .foregroundColor(.wcagSecondaryText)
            }

            Section("Global Shortcuts") {
                shortcutRow(
                    "Quick Capture",
                    action: .quickCapture,
                    shortcut: $settings.quickCaptureShortcut,
                    other: settings.searchShortcut,
                    fallback: .quickCaptureDefault
                )
                shortcutRow(
                    "Search All Notes",
                    action: .search,
                    shortcut: $settings.searchShortcut,
                    other: settings.quickCaptureShortcut,
                    fallback: .searchDefault
                )

                Text("These work from any app. Shortcuts that use only ⌥ stop that key from typing special characters, such as ƒ or ˜, in other apps.")
                    .font(.caption)
                    .foregroundColor(.wcagSecondaryText)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
                HStack {
                    Text("Version \(AppVersion.current.description)")
                    Spacer()
                    Button("Check Now") {
                        Task { await updates.check(userInitiated: true) }
                    }
                    .disabled(updates.state == .checking)
                }
                Text((updates.lastCheck.map { "Last checked \($0.formatted(date: .abbreviated, time: .shortened)). " } ?? "")
                     + "When a new version is out, Scattered Notes shows what changed and asks before installing it.")
                    .font(.caption)
                    .foregroundColor(.wcagSecondaryText)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func shortcutRow(
        _ title: String,
        action: HotKeyAction,
        shortcut: Binding<HotKeyShortcut>,
        other: HotKeyShortcut,
        fallback: HotKeyShortcut
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                ShortcutRecorderView(shortcut: shortcut) { recorded in
                    recorded == other ? "Already used by the other shortcut." : nil
                }
                Button("Reset") { shortcut.wrappedValue = fallback }
                    .disabled(shortcut.wrappedValue == fallback)
            }
            if hotKeys.failures[action] != nil {
                Text("\(shortcut.wrappedValue.displayString) is taken by the system or another app. Pick a different one.")
                    .font(.caption)
                    .foregroundColor(.wcagOrange)
            }
        }
    }
}
