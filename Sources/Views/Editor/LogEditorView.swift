import SwiftUI
import AppKit

/// The text view of a log note. A class of its own so the rest of the app can tell it from other text views.
final class LogTextView: NSTextView {}

/// The editor of a log note (see `LogLines`): plain text in a monospaced font, where the time of each line is part
/// of the text, at the start of the line, as in a log file. Pressing Return starts a new line with the time of that
/// moment already written, so the whole text can be copied as it is.
struct LogEditorView: NSViewRepresentable {
    @Binding var content: String
    var fontSize: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = LogTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.setAccessibilityIdentifier("noteText")
        textView.delegate = context.coordinator
        scrollView.documentView = textView

        context.coordinator.textView = textView
        textView.string = content
        apply(fontSize: fontSize, to: textView)
        Self.colour(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        apply(fontSize: fontSize, to: textView)
        // The note changed from outside, such as a newer version from another device
        if textView.string != content {
            let selection = textView.selectedRange()
            textView.string = content
            let length = (content as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            apply(fontSize: fontSize, to: textView, force: true)
            Self.colour(textView)
        }
    }

    /// The text in the normal colour and the times in a quieter one, so the entries read first
    static func colour(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: all)
        for range in LogLines.stampRanges(in: textView.string) {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
        storage.endEditing()
        // What is typed next is text, even right after a time
        textView.typingAttributes[.foregroundColor] = NSColor.labelColor
    }

    /// The system's monospaced font (SF Mono on a Mac)
    private func apply(fontSize: CGFloat, to textView: NSTextView, force: Bool = false) {
        guard force || textView.font?.pointSize != fontSize || textView.font?.isFixedPitch != true else { return }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        textView.font = font
        textView.defaultParagraphStyle = style
        textView.typingAttributes = [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.labelColor]
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.textStorage?.addAttributes([.font: font, .paragraphStyle: style, .foregroundColor: NSColor.labelColor], range: all)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LogEditorView
        weak var textView: NSTextView?

        init(_ parent: LogEditorView) { self.parent = parent }

        /// Return starts a new line with the time of now already at its start
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let line = LogLines.format(Date(), calendar: .current) + " "
            textView.insertText("\n" + line, replacementRange: textView.selectedRange())
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            LogEditorView.colour(textView)
            if parent.content != textView.string { parent.content = textView.string }
        }
    }
}
