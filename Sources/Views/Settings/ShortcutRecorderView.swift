import SwiftUI
import AppKit

/// A button that records a new shortcut: click it, then press the key combination. Esc cancels.
struct ShortcutRecorderView: View {
    @Binding var shortcut: HotKeyShortcut
    /// Returns a reason to reject a recorded shortcut, e.g. because another action already uses it
    var validate: (HotKeyShortcut) -> String? = { _ in nil }

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: { isRecording ? stopRecording() : startRecording() }) {
                Text(isRecording ? "Press shortcut…" : shortcut.displayString)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            .help("Click, then press the new shortcut. Esc cancels.")

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.wcagOrange)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        message = nil
        isRecording = true
        EscapeToClose.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stopRecording()
                return nil
            }
            guard let recorded = HotKeyShortcut(event: event) else {
                message = "Include ⌘, ⌥ or ⌃."
                return nil
            }
            if let problem = validate(recorded) {
                message = problem
                return nil
            }
            shortcut = recorded
            stopRecording()
            if recorded.typesACharacter {
                message = "Typing \(recorded.character.uppercased()) with ⌥ will trigger this instead of typing a character."
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        EscapeToClose.isRecordingShortcut = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
