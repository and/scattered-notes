import SwiftUI
import UIKit

/// The editor of a log note on the iPhone (see `LogLines`): plain text in a monospaced font, where the time of each
/// line is part of the text, at the start of the line, as in a log file. Return starts a new line with the time of
/// that moment already written. The times are drawn in a quieter grey, and the "T" and the UTC offset lighter still.
struct LogTextEditor: UIViewRepresentable {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.accessibilityIdentifier = "noteText"
        view.text = text
        Self.style(view)
        // Typing "Log -" in a note swaps the editor while the cursor is in it: the cursor goes just after the dash
        if focused.wrappedValue { view.selectedRange = NSRange(location: LogLines.headingEnd(in: text) ?? (text as NSString).length, length: 0) }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        // The note changed from outside, such as a newer version from another device
        if view.text != text {
            let selection = view.selectedRange
            view.text = text
            view.selectedRange = NSRange(location: min(selection.location, (text as NSString).length), length: 0)
            Self.style(view)
        }
        if focused.wrappedValue, !view.isFirstResponder { view.becomeFirstResponder() }
    }

    /// The system's monospaced font, the text in the normal colour, the times quieter
    static func style(_ view: UITextView) {
        // The text and the times share one size, a little under the system's body size, so a small phone keeps room
        // for the entry
        let size = (UIFont.preferredFont(forTextStyle: .body).pointSize * 0.85).rounded()
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        // The UTC offset stays in the file but is drawn out of the way: a size too small to see, and clear
        let hidden = UIFont.monospacedSystemFont(ofSize: 1, weight: .regular)
        let storage = view.textStorage
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttributes([.font: font, .foregroundColor: UIColor.label], range: all)
        let styling = LogLines.stampStyling(in: view.text)
        for range in styling.quiet { storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range) }
        // Each time has two faint parts, the "T" and then the offset
        for (index, range) in styling.faint.enumerated() {
            if index % 2 == 0 {
                storage.addAttribute(.foregroundColor, value: UIColor.label.withAlphaComponent(0.17), range: range)
            } else {
                storage.addAttributes([.foregroundColor: UIColor.clear, .font: hidden], range: range)
            }
        }
        storage.endEditing()
        // What is typed next is text, even right after a time
        view.typingAttributes = [.font: font, .foregroundColor: UIColor.label]
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: LogTextEditor

        init(_ parent: LogTextEditor) { self.parent = parent }

        /// Return starts a new line with the time of now already at its start
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement == "\n" else { return true }
            let time = LogLines.format(Date(), calendar: .current) + " "
            // The longer text is not the "\n" this method looks for, so it goes in as typed
            textView.insertText("\n" + time)
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            LogTextEditor.style(textView)
            if parent.text != textView.text { parent.text = textView.text }
        }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.focused.wrappedValue = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.focused.wrappedValue = false }
    }
}
