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
}

public struct SettingsView: View {
    @ObservedObject var storageManager = NoteStorageManager.shared
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var hotKeys = GlobalHotKeyManager.shared

    public init() {}

    public var body: some View {
        Form {
            Section("Notes Folder") {
                Text(settings.notesDirectoryURL.path)
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
                    Button("Use Default") {
                        StorageFolderPicker.relocate(to: AppSettings.defaultNotesDirectoryURL, storageManager: storageManager)
                    }
                    .disabled(settings.notesDirectoryURL.standardizedFileURL == AppSettings.defaultNotesDirectoryURL.standardizedFileURL)
                }

                Text("Changing the folder moves all existing notes, projects and areas into it.")
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
