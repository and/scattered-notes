import AppKit
import SwiftUI

/// The list of names that opens under the cursor while a `+project`, `#tag` or `@person` is being typed,
/// in the note editor, the log editor and Quick Capture. ↑↓ choose, Return or Tab completes, Esc closes
/// the list and leaves the text as typed. The names come from `MentionSuggestions`.
@MainActor
final class MentionCompleter: ObservableObject {
    static let shared = MentionCompleter()

    @Published private(set) var items: [String] = []
    @Published private(set) var selected = 0

    private weak var textView: NSTextView?
    private var token: MentionSuggestions.Token?
    /// Where the mark that Esc closed the list for starts: the list stays closed until that mark is gone
    private var dismissedStart: Int?
    private var panel: CompleterPanel?
    private var installed = false

    var isShowing: Bool { panel?.isVisible == true }

    func install() {
        guard !installed else { return }
        installed = true
        for name in [NSText.didChangeNotification, NSTextView.didChangeSelectionNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // Delivered on the main queue, so the text view is only ever touched on the main thread
                nonisolated(unsafe) let view = note.object as? NSTextView
                MainActor.assumeIsolated { self?.evaluate(view) }
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
    }

    // MARK: - Deciding what to show

    private func evaluate(_ view: NSTextView?) {
        guard let view, view.isEditable, !view.isFieldEditor, !view.hasMarkedText(),
              view.selectedRange().length == 0, view.window?.isKeyWindow == true,
              !(view.window is CompleterPanel) else { return hide() }
        let caret = view.selectedRange().location
        guard let found = MentionSuggestions.token(in: view.string, caret: caret) else {
            dismissedStart = nil
            return hide()
        }
        if dismissedStart == found.range.location { return hide() }
        let storage = NoteStorageManager.shared
        let names = MentionSuggestions.suggestions(for: found, notes: storage.notes, projects: storage.projects.map(\.name))
        guard !names.isEmpty else { return hide() }

        if token?.range.location != found.range.location || token?.kind != found.kind || selected >= names.count { selected = 0 }
        textView = view
        token = found
        items = names
        show(near: view, at: found.range.location)
    }

    // MARK: - The list on screen

    private func show(near view: NSTextView, at location: Int) {
        let panel = self.panel ?? CompleterPanel(completer: self)
        self.panel = panel
        let height = CGFloat(items.count) * 26 + 10
        panel.setContentSize(NSSize(width: 240, height: height))
        let caret = view.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        var origin = NSPoint(x: caret.minX, y: caret.minY - height - 4)
        if let screen = view.window?.screen ?? NSScreen.main, origin.y < screen.visibleFrame.minY {
            origin.y = caret.maxY + 4
        }
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
    }

    private func hide() {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        items = []
        token = nil
    }

    // MARK: - Keys and choosing

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isShowing, let view = textView, event.window === view.window, !items.isEmpty else { return false }
        let blocked = event.modifierFlags.intersection([.command, .control, .option])
        guard blocked.isEmpty else { return false }
        switch event.keyCode {
        case 125: selected = (selected + 1) % items.count; return true
        case 126: selected = (selected - 1 + items.count) % items.count; return true
        case 36, 76, 48: accept(selected); return true
        case 53:
            dismissedStart = token?.range.location
            hide()
            return true
        default: return false
        }
    }

    func accept(_ index: Int) {
        guard items.indices.contains(index), let view = textView, let token else { return }
        let text = MentionSuggestions.insertion(for: items[index], kind: token.kind)
        hide()
        // Through the text view, so ⌘Z undoes it and the note's text follows
        view.insertText(text, replacementRange: token.range)
    }
}

/// The floating list: never takes the keyboard from the text
private final class CompleterPanel: NSPanel {
    init(completer: MentionCompleter) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 240, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        contentView = NSHostingView(rootView: MentionListView(completer: completer))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct MentionListView: View {
    @ObservedObject var completer: MentionCompleter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(completer.items.enumerated()), id: \.offset) { index, name in
                Text(name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                    .foregroundColor(index == completer.selected ? .white : .primary)
                    .background(index == completer.selected ? Color.wcagBlue : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                    .onTapGesture { completer.accept(index) }
            }
        }
        .padding(5)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.wcagBorder, lineWidth: 1))
        .accessibilityIdentifier("mentionList")
    }
}
