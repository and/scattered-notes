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
