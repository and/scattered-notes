import AppKit

extension Notification.Name {
    static let focusNoteEditor = Notification.Name("ScatteredNotes.focusNoteEditor")
}

/// Moves keyboard focus into a note's text so the user can start typing.
@MainActor
enum EditorFocus {
    struct Request {
        let noteID: UUID
        /// Search words that led to the note; the cursor goes after the first one found in the text
        let terms: [String]
    }

    /// The request the next editor for that note should act on
    static var pending: Request?

    static func request(noteID: UUID, terms: [String] = []) {
        pending = Request(noteID: noteID, terms: terms)
        NotificationCenter.default.post(name: .focusNoteEditor, object: nil)
    }

    /// UTF-16 offset for the cursor: just after the first search term found in `text`, else the end of the text.
    static func cursorOffset(in text: String, terms: [String]) -> Int {
        let nsText = text as NSString
        for term in terms where !term.isEmpty {
            let range = nsText.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
            if range.location != NSNotFound { return range.location + range.length }
        }
        return nsText.length
    }

    /// Focuses the editor's text view and places the cursor. The view may not exist yet when a
    /// note was just opened, so this retries for about a second.
    static func focusTextView(showing text: String, atOffset offset: Int, attemptsLeft: Int = 16) {
        if let window = NSApp.mainWindow ?? NSApp.keyWindow,
           window.attachedSheet == nil,
           let textView = editorTextView(in: window.contentView, showing: text) {
            window.makeFirstResponder(textView)
            let range = NSRange(location: min(offset, (textView.string as NSString).length), length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            return
        }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            focusTextView(showing: text, atOffset: offset, attemptsLeft: attemptsLeft - 1)
        }
    }

    /// Where a position in `old` lands in `new` when `new` is `old` with date markers written into its
    /// lines: the same place in the words, so a cursor typing at the end of a line stays before the marker
    /// written there, and one right after a marker stays after it.
    static func mappedOffset(_ offset: Int, from old: String, to new: String) -> Int {
        let oldMarkers = AgendaExtractor.markerRanges(in: old)
        let newMarkers = AgendaExtractor.markerRanges(in: new)
        func isMarker(_ index: Int, _ markers: [NSRange]) -> Bool {
            markers.contains { index >= $0.location && index < $0.location + $0.length }
        }
        let wordsBefore = (0..<min(offset, (old as NSString).length)).filter { !isMarker($0, oldMarkers) }.count
        let afterMarker = oldMarkers.contains { $0.location + $0.length == offset }
        var words = 0
        var result: Int?
        let length = (new as NSString).length
        for index in 0...length {
            if words == wordsBefore {
                result = index
                if !afterMarker { break }
            }
            if index < length, !isMarker(index, newMarkers) { words += 1 }
            if words > wordsBefore { break }
        }
        return result ?? min(offset, length)
    }

    /// Keeps the cursor where it was in the same text when the editor's text is about to be replaced
    /// by `new`, e.g. when the app writes a date marker into the line being typed.
    static func keepCursor(from old: String, to new: String, attemptsLeft: Int = 10) {
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow,
              let textView = editorTextView(in: window.contentView, showing: old),
              window.firstResponder === textView else { return }
        let selection = textView.selectedRange()
        let start = mappedOffset(selection.location, from: old, to: new)
        let end = mappedOffset(selection.location + selection.length, from: old, to: new)
        restoreSelection(NSRange(location: start, length: end - start), in: textView, showing: new, attemptsLeft: attemptsLeft)
    }

    private static func restoreSelection(_ range: NSRange, in textView: NSTextView, showing text: String, attemptsLeft: Int) {
        if textView.string == text {
            textView.setSelectedRange(range)
            return
        }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            restoreSelection(range, in: textView, showing: text, attemptsLeft: attemptsLeft - 1)
        }
    }

    private static func editorTextView(in view: NSView?, showing text: String) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.isEditable, !textView.isFieldEditor, textView.string == text {
            return textView
        }
        for subview in view.subviews {
            if let found = editorTextView(in: subview, showing: text) { return found }
        }
        return nil
    }
}
