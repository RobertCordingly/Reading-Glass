import AppKit
import SwiftUI

/// An NSTextView wrapper that displays text with word highlighting and supports
/// clicking on a word to jump the TTS cursor to that position.
struct ReaderTextView: NSViewRepresentable {
    let text: String
    let cursorUTF16: Int
    let cursorLengthUTF16: Int
    var isPlaying: Bool = false
    let onWordClicked: (Int) -> Void  // passes UTF-16 offset of clicked word start

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ClickableTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.onWordClicked = context.coordinator.onWordClicked
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 60, right: 0)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! ClickableTextView
        textView.onWordClicked = onWordClicked

        // Only update text content if it actually changed
        let currentPlain = textView.textStorage?.string ?? ""
        if currentPlain != text {
            let attributed = buildAttributedString()
            textView.textStorage?.setAttributedString(attributed)
        } else {
            // Just update highlighting
            updateHighlighting(textView)
        }

        // Scroll to keep the highlighted word visible (only while reading)
        if isPlaying {
            let highlightRange = currentHighlightNSRange()
            if highlightRange.length > 0 && highlightRange.location < (textView.string as NSString).length {
                textView.scrollRangeToVisible(highlightRange)
            }
        }

        context.coordinator.text = text
        context.coordinator.onWordClicked = onWordClicked
    }

    /// Returns the NSRange of the currently highlighted word.
    private func currentHighlightNSRange() -> NSRange {
        let utf16 = text.utf16
        let start = min(cursorUTF16, utf16.count)
        let length = min(cursorLengthUTF16, utf16.count - start)

        if length > 0 && start < utf16.count {
            return NSRange(location: start, length: length)
        } else if start < utf16.count {
            return findWordRange(at: start)
        }
        return NSRange(location: 0, length: 0)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: text, onWordClicked: onWordClicked)
    }

    private func buildAttributedString() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .justified

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle,
            ]
        )

        // Apply highlight to current word
        let utf16 = text.utf16
        let start = min(cursorUTF16, utf16.count)
        let length = min(cursorLengthUTF16, utf16.count - start)

        if length > 0 && start < utf16.count {
            attributed.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: NSRange(location: start, length: length))
        } else if start < utf16.count {
            // No length — highlight the word at cursor
            let wordRange = findWordRange(at: start)
            if wordRange.length > 0 {
                attributed.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: wordRange)
            }
        }

        return attributed
    }

    private func updateHighlighting(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)

        let utf16 = text.utf16
        let start = min(cursorUTF16, utf16.count)
        let length = min(cursorLengthUTF16, utf16.count - start)

        if length > 0 && start < utf16.count {
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: NSRange(location: start, length: length))
        } else if start < utf16.count {
            let wordRange = findWordRange(at: start)
            if wordRange.length > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: wordRange)
            }
        }
        storage.endEditing()
    }

    private func findWordRange(at utf16Offset: Int) -> NSRange {
        let nsString = text as NSString
        guard utf16Offset < nsString.length else { return NSRange(location: utf16Offset, length: 0) }

        // Expand from the offset to find word boundaries
        var wordStart = utf16Offset
        var wordEnd = utf16Offset

        while wordStart > 0 {
            let c = nsString.character(at: wordStart - 1)
            if let scalar = Unicode.Scalar(c), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                break
            }
            wordStart -= 1
        }

        while wordEnd < nsString.length {
            let c = nsString.character(at: wordEnd)
            if let scalar = Unicode.Scalar(c), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                break
            }
            wordEnd += 1
        }

        return NSRange(location: wordStart, length: wordEnd - wordStart)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: String
        var onWordClicked: (Int) -> Void

        init(text: String, onWordClicked: @escaping (Int) -> Void) {
            self.text = text
            self.onWordClicked = onWordClicked
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            return false
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            return false
        }
    }

    /// Subclass to intercept mouse clicks and report word positions
    class ClickableTextView: NSTextView {
        var onWordClicked: ((Int) -> Void)?

        override func mouseDown(with event: NSEvent) {
            let localPoint = convert(event.locationInWindow, from: nil)
            let charIndex = characterIndexForInsertion(at: localPoint)
            guard charIndex < (string as NSString).length else { return }

            let nsString = string as NSString
            var wordStart = charIndex

            while wordStart > 0 {
                let c = nsString.character(at: wordStart - 1)
                if let scalar = Unicode.Scalar(c), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    break
                }
                wordStart -= 1
            }

            onWordClicked?(wordStart)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}
