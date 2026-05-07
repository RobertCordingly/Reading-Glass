#if os(iOS)
import SwiftUI
import UIKit

/// UITextView wrapper for iPadOS — mirrors the macOS ReaderTextView API.
/// Displays attributed text with word highlighting and reports tapped word offsets.
struct ReaderTextView: UIViewRepresentable {
    let text: String
    let cursorUTF16: Int
    let cursorLengthUTF16: Int
    var isPlaying: Bool = false
    /// UTF-16 range of the chunk the AI cleanup pipeline is currently rewriting.
    /// `nil` when no cleanup is in flight. Drawn as a soft yellow highlight.
    var cleaningRange: NSRange? = nil
    /// Bumped by the parent every time the user picks a search result; forces a
    /// scroll-into-view even when playback is stopped.
    var scrollVersion: Int = 0
    let onWordClicked: (Int) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = ClickableTextView()
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.isSelectable = false
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 60, right: 8)
        textView.backgroundColor = .clear
        textView.onWordTapped = context.coordinator.handleTap
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let clickable = textView as! ClickableTextView
        clickable.onWordTapped = onWordClicked

        let currentPlain = textView.attributedText?.string ?? ""
        if currentPlain != text {
            textView.attributedText = buildAttributedString()
        } else {
            updateHighlighting(textView)
        }

        let scrollRequested = context.coordinator.lastScrollVersion != scrollVersion
        if isPlaying || scrollRequested {
            let range = currentHighlightNSRange()
            if range.length > 0, range.location + range.length <= (textView.text as NSString).length {
                textView.scrollRangeToVisible(range)
            }
        }
        context.coordinator.lastScrollVersion = scrollVersion

        context.coordinator.text = text
        context.coordinator.onWordClicked = onWordClicked
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: text, onWordClicked: onWordClicked)
    }

    // MARK: - Helpers

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

    private static let cleaningHighlightColor: UIColor = UIColor.systemYellow.withAlphaComponent(0.28)

    private func buildAttributedString() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .justified

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle,
            ]
        )

        applyCleaningHighlight(to: attributed)
        applySpeechHighlight(to: attributed)

        return attributed
    }

    private func updateHighlighting(_ textView: UITextView) {
        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
        storage.removeAttribute(.backgroundColor, range: fullRange)

        applyCleaningHighlight(to: storage)
        applySpeechHighlight(to: storage)

        storage.endEditing()
    }

    private func clampedCleaningRange() -> NSRange? {
        guard let range = cleaningRange, range.length > 0 else { return nil }
        let total = (text as NSString).length
        guard range.location < total else { return nil }
        let length = min(range.length, total - range.location)
        return NSRange(location: range.location, length: length)
    }

    private func applyCleaningHighlight(to storage: NSMutableAttributedString) {
        guard let range = clampedCleaningRange() else { return }
        storage.addAttribute(.backgroundColor, value: Self.cleaningHighlightColor, range: range)
    }

    private func applySpeechHighlight(to storage: NSMutableAttributedString) {
        let utf16 = text.utf16
        let start = min(cursorUTF16, utf16.count)
        let length = min(cursorLengthUTF16, utf16.count - start)

        if length > 0 && start < utf16.count {
            storage.addAttribute(.foregroundColor, value: UIColor.tintColor, range: NSRange(location: start, length: length))
        } else if start < utf16.count {
            let wordRange = findWordRange(at: start)
            if wordRange.length > 0 {
                storage.addAttribute(.foregroundColor, value: UIColor.tintColor, range: wordRange)
            }
        }
    }

    private func findWordRange(at utf16Offset: Int) -> NSRange {
        let nsString = text as NSString
        guard utf16Offset < nsString.length else { return NSRange(location: utf16Offset, length: 0) }

        var wordStart = utf16Offset
        var wordEnd = utf16Offset

        while wordStart > 0 {
            let c = nsString.character(at: wordStart - 1)
            if let scalar = Unicode.Scalar(c), CharacterSet.whitespacesAndNewlines.contains(scalar) { break }
            wordStart -= 1
        }

        while wordEnd < nsString.length {
            let c = nsString.character(at: wordEnd)
            if let scalar = Unicode.Scalar(c), CharacterSet.whitespacesAndNewlines.contains(scalar) { break }
            wordEnd += 1
        }

        return NSRange(location: wordStart, length: wordEnd - wordStart)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var text: String
        var onWordClicked: (Int) -> Void
        var lastScrollVersion: Int = 0

        init(text: String, onWordClicked: @escaping (Int) -> Void) {
            self.text = text
            self.onWordClicked = onWordClicked
        }

        func handleTap(at utf16Offset: Int) {
            onWordClicked(utf16Offset)
        }
    }

    // MARK: - Tap-aware UITextView

    class ClickableTextView: UITextView {
        var onWordTapped: ((Int) -> Void)?

        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            addGestureRecognizer(tap)
        }

        required init?(coder: NSCoder) { fatalError() }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: self)
            // Adjust for text container inset
            let adjustedPoint = CGPoint(
                x: point.x - textContainerInset.left - textContainer.lineFragmentPadding,
                y: point.y - textContainerInset.top
            )
            let charIndex = layoutManager.characterIndex(
                for: adjustedPoint,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            guard charIndex < (text as NSString).length else { return }

            // Walk back to word start
            let nsString = text as NSString
            var wordStart = charIndex
            while wordStart > 0 {
                let c = nsString.character(at: wordStart - 1)
                if let scalar = Unicode.Scalar(c), CharacterSet.whitespacesAndNewlines.contains(scalar) { break }
                wordStart -= 1
            }

            onWordTapped?(wordStart)
        }
    }
}
#endif
