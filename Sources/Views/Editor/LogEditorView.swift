import SwiftUI
import AppKit

/// The text view of a log note. A class of its own so the rest of the app can tell it from other text views.
final class LogTextView: NSTextView {}

/// The editor of a log note (see `LogLines`): plain text with a column at the right that shows when each line was
/// written, like the line numbers of a code editor but at the other side. The file's time markers are taken off
/// the text shown here and put back when the text is handed on, so the column is the only place they appear.
struct LogEditorView: NSViewRepresentable {
    /// The note's whole text, markers included
    @Binding var content: String
    var fontSize: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> LogEditorContainer {
        let container = LogEditorContainer()
        container.textView.delegate = context.coordinator
        context.coordinator.container = container
        context.coordinator.load(content)
        container.apply(fontSize: fontSize)
        return container
    }

    func updateNSView(_ container: LogEditorContainer, context: Context) {
        context.coordinator.parent = self
        container.apply(fontSize: fontSize)
        // The note changed from outside, such as a newer version from another device
        if content != context.coordinator.lastHandedOn { context.coordinator.load(content) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LogEditorView
        weak var container: LogEditorContainer?
        /// The last text this editor gave to the note, or took from it: a different one means an outside change
        var lastHandedOn = ""

        init(_ parent: LogEditorView) { self.parent = parent }

        func load(_ content: String) {
            guard let container else { return }
            let log = LogLines.parse(content)
            let selection = container.textView.selectedRange()
            container.textView.string = log.text
            container.stamps = log.stamps
            let length = (log.text as NSString).length
            container.textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            lastHandedOn = content
            container.gutter.needsDisplay = true
        }

        /// Called before a change: brings the times in step with it
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard let container else { return true }
            LogLines.edit(stamps: &container.stamps, in: textView.string, replacing: range, with: replacementString ?? "", now: Date())
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let container else { return }
            let text = container.textView.string
            let merged = LogLines.serialize(text: text, stamps: container.stamps)
            lastHandedOn = merged
            container.gutter.needsDisplay = true
            if parent.content != merged { parent.content = merged }
        }
    }
}

/// The text with the column of times at its right
final class LogEditorContainer: NSView {
    static let gutterWidth: CGFloat = 138

    let scrollView = NSScrollView()
    let textView: LogTextView
    let gutter = LogGutterView()
    /// The time of each line, `nil` for none. Kept in step with the text by `LogLines.edit`.
    var stamps: [Date?] = [] { didSet { gutter.needsDisplay = true } }

    init() {
        // TextKit 1, set up by hand: the gutter asks the layout manager where each line is
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        textView = LogTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: container)
        super.init(frame: .zero)

        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.setAccessibilityIdentifier("noteText")

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(scrollView)

        gutter.owner = self
        addSubview(gutter)

        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func scrolled() { gutter.needsDisplay = true }

    func apply(fontSize: CGFloat) {
        guard textView.font?.pointSize != fontSize else { return }
        let font = NSFont.systemFont(ofSize: fontSize)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        textView.font = font
        textView.defaultParagraphStyle = style
        textView.typingAttributes = [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.labelColor]
        // Existing text takes the new look too
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.textStorage?.addAttributes([.font: font, .paragraphStyle: style, .foregroundColor: NSColor.labelColor], range: all)
        gutter.needsDisplay = true
    }

    override func layout() {
        super.layout()
        let width = max(bounds.width - Self.gutterWidth, 100)
        scrollView.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        gutter.frame = NSRect(x: width, y: 0, width: min(Self.gutterWidth, bounds.width), height: bounds.height)
        gutter.needsDisplay = true
    }
}

/// Draws each line's time at the right, level with the line
final class LogGutterView: NSView {
    weak var owner: LogEditorContainer?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]

    override func draw(_ dirtyRect: NSRect) {
        guard let owner, let layout = owner.textView.layoutManager, let container = owner.textView.textContainer else { return }
        let text = owner.textView.string as NSString
        let origin = owner.textView.textContainerOrigin
        let scrolled = owner.scrollView.contentView.bounds.origin.y

        var line = 0
        var start = 0
        while start <= text.length {
            let rect: NSRect
            if start < text.length {
                let glyph = layout.glyphIndexForCharacter(at: start)
                rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            } else {
                // The empty line after a final newline
                rect = layout.extraLineFragmentRect
                if rect.isEmpty { break }
            }
            let y = rect.minY + origin.y - scrolled
            if y > bounds.height { break }
            if y + rect.height >= 0, line < owner.stamps.count, let stamp = owner.stamps[line] {
                let label = Self.label(for: stamp) as NSString
                let size = label.size(withAttributes: Self.attributes)
                // Level with the first row of the line's text
                let top = y + (min(rect.height, 26) - size.height) / 2 + 2
                label.draw(at: NSPoint(x: bounds.width - size.width - 10, y: top), withAttributes: Self.attributes)
            }
            line += 1
            guard start < text.length else { break }
            let paragraph = text.paragraphRange(for: NSRange(location: start, length: 0))
            start = NSMaxRange(paragraph)
            // A paragraph that ends without a newline is the last one
            if paragraph.length == 0 || !text.substring(with: paragraph).hasSuffix("\n") { break }
        }
        _ = container
    }

    /// "2026-11-05 11:34:07", in the reader's time zone
    static func label(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
