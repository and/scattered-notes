import AppKit
import SwiftUI

/// The window that says an update is available, shows what is in it, and lets the user choose.
@MainActor
enum UpdateWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Software Update"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: UpdateView { close() })
        window.center()
        // Closing the window counts as "Remind Me Later", so the next daily check can run
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                switch UpdateChecker.shared.state {
                case .downloading, .installing: break
                default: UpdateChecker.shared.remindLater()
                }
                UpdateWindow.window = nil
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    static func close() {
        window?.close()
        window = nil
    }
}

struct UpdateView: View {
    @ObservedObject var checker = UpdateChecker.shared
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .foregroundColor(.wcagSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if case .available(let release) = checker.state {
                Text("What's new")
                    .font(.headline)
                MarkdownRendererView(content: .constant(release.notes.isEmpty ? "No release notes." : release.notes))
                    .frame(minHeight: 200)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.wcagBorder.opacity(0.5)))
            }

            Toggle("Check for updates automatically", isOn: $checker.automaticallyChecks)

            HStack {
                buttons
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: isAvailable ? 420 : 0)
    }

    private var isAvailable: Bool {
        if case .available = checker.state { return true }
        return false
    }

    private var title: String {
        switch checker.state {
        case .available(let release):
            return "Scattered Notes \(release.version?.description ?? release.tagName) is available"
        case .checking: return "Checking for updates…"
        case .upToDate: return "Scattered Notes is up to date"
        case .downloading: return "Downloading the update…"
        case .installing: return "Installing the update…"
        case .failed: return "Update failed"
        case .idle: return "Software Update"
        }
    }

    private var subtitle: String {
        switch checker.state {
        case .available:
            return "You have version \(AppVersion.current). Your notes are plain files in your notes folder and are not touched by updating."
        case .upToDate: return "Version \(AppVersion.current) is the newest version."
        case .downloading, .installing: return "Scattered Notes will quit, update and open again. Unsaved edits are saved first."
        case .failed(let message): return message
        case .checking, .idle: return "Version \(AppVersion.current)"
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch checker.state {
        case .available(let release):
            Button("Skip This Version") {
                checker.skip(release)
                onClose()
            }
            Spacer()
            Button("Remind Me Later") {
                checker.remindLater()
                onClose()
            }
            .keyboardShortcut(.cancelAction)
            Button(checker.canInstallInPlace ? "Install and Relaunch" : "Download") {
                Task { await checker.install(release) }
            }
            .keyboardShortcut(.defaultAction)
        case .downloading, .installing, .checking:
            ProgressView().controlSize(.small)
            Spacer()
        case .failed:
            Button("Open Releases Page") {
                NSWorkspace.shared.open(UpdateChecker.releasesPage)
            }
            Spacer()
            Button("Close") {
                checker.remindLater()
                onClose()
            }
            .keyboardShortcut(.defaultAction)
        case .upToDate, .idle:
            Spacer()
            Button("OK") {
                checker.remindLater()
                onClose()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
