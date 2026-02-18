import AVFoundation
import SwiftUI

class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    @Published var isPlaying = false
    @Published var isPaused = false

    /// Current cursor position as a UTF-16 offset into the full text.
    /// AVSpeechSynthesizer reports NSRange in UTF-16 units.
    @Published var cursorUTF16: Int = 0
    @Published var cursorLengthUTF16: Int = 0

    private var fullText = ""
    /// UTF-16 offset from the start of fullText to the start of the utterance text
    private var speakingUTF16Offset = 0

    /// Speed multiplier (0.5x to 4.0x), converted to AVSpeechUtterance rate on each utterance
    var speedMultiplier: Float = 2.0

    /// Available TTS voices
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoiceID: String = ""

    override init() {
        super.init()
        synthesizer.delegate = self
        loadVoices()
    }

    private func loadVoices() {
        // Get all English voices, deduplicated by name, sorted by name
        var seenNames = Set<String>()
        availableVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
            .filter { seenNames.insert($0.name).inserted }

        // Default to Samantha (Enhanced), then Samantha, then any en-US voice, then any available
        if let samanthaEnhanced = availableVoices.first(where: { $0.name == "Samantha (Enhanced)" }) {
            selectedVoiceID = samanthaEnhanced.identifier
        } else if let samantha = availableVoices.first(where: { $0.name == "Samantha" }) {
            selectedVoiceID = samantha.identifier
        } else if let defaultVoice = availableVoices.first(where: { $0.language == "en-US" }) {
            selectedVoiceID = defaultVoice.identifier
        } else if let first = availableVoices.first {
            selectedVoiceID = first.identifier
        }
    }

    /// Converts our speed multiplier (0.5-4.0) to AVSpeechUtterance rate.
    /// The AVSpeechUtterance rate scale is highly non-linear:
    ///   0.5 = default/normal, values above 0.6 are very fast.
    /// We map our multiplier so 1x = 0.5 (default), with a gentle slope.
    private func avRate() -> Float {
        // 0.5x -> 0.4,  1x -> 0.5,  2x -> 0.6,  3x -> 0.7,  4x -> 0.8
        let rate = 0.5 + (speedMultiplier - 1.0) * 0.1
        return min(max(Float(rate), AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    /// Returns the Range<String.Index> for the currently highlighted word, or nil if text is empty.
    func highlightRange(in text: String) -> Range<String.Index>? {
        let utf16 = text.utf16
        guard !text.isEmpty else { return nil }

        let clampedStart = min(cursorUTF16, utf16.count)
        let clampedEnd = min(cursorUTF16 + max(cursorLengthUTF16, 1), utf16.count)

        var start = String.Index(utf16Offset: clampedStart, in: text)
        var end = String.Index(utf16Offset: clampedEnd, in: text)

        // Ensure indices are on grapheme cluster boundaries
        start = text.index(text.startIndex, offsetBy: text.distance(from: text.startIndex, to: start))

        guard start < text.endIndex else {
            return nil
        }

        // If we have no length (e.g. initial state), find the word at cursor
        if cursorLengthUTF16 == 0 {
            var wordEnd = start
            while wordEnd < text.endIndex && !text[wordEnd].isWhitespace {
                wordEnd = text.index(after: wordEnd)
            }
            if wordEnd == start && start < text.endIndex {
                wordEnd = text.index(after: start)
            }
            return start..<wordEnd
        }

        if end > text.endIndex { end = text.endIndex }
        end = text.index(text.startIndex, offsetBy: text.distance(from: text.startIndex, to: end))

        if end <= start && start < text.endIndex {
            end = text.index(after: start)
        }

        return start..<end
    }

    func play(text: String) {
        fullText = text
        guard !text.isEmpty else { return }

        // Always start fresh from the current cursor position
        synthesizer.stopSpeaking(at: .immediate)

        let utf16 = text.utf16
        let clampedOffset = min(cursorUTF16, utf16.count)
        let startIndex = String.Index(utf16Offset: clampedOffset, in: text)

        let substring = String(text[startIndex...])
        guard !substring.isEmpty else { return }

        speakingUTF16Offset = clampedOffset

        let utterance = AVSpeechUtterance(string: substring)
        utterance.rate = avRate()
        if !selectedVoiceID.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(identifier: selectedVoiceID)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        synthesizer.speak(utterance)
        isPlaying = true
        isPaused = false
    }

    func pause() {
        synthesizer.stopSpeaking(at: .immediate)
        isPaused = false
        isPlaying = false
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false
    }

    func skipForward(in text: String) {
        stop()

        let utf16 = text.utf16
        guard cursorUTF16 < utf16.count else { return }
        let startIdx = String.Index(utf16Offset: cursorUTF16, in: text)

        let remaining = text[startIdx...]
        if let dotIndex = remaining.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            var nextStart = text.index(after: dotIndex)
            while nextStart < text.endIndex && text[nextStart].isWhitespace {
                nextStart = text.index(after: nextStart)
            }
            if nextStart < text.endIndex {
                cursorUTF16 = nextStart.utf16Offset(in: text)
                cursorLengthUTF16 = 0
            }
        }
    }

    func skipBackward(in text: String) {
        stop()

        let utf16 = text.utf16
        guard cursorUTF16 > 0, !text.isEmpty else { return }

        let clampedOffset = min(cursorUTF16, utf16.count)
        let currentIdx = String.Index(utf16Offset: clampedOffset, in: text)

        let before = text[text.startIndex..<currentIdx]
        var searchEnd = before.endIndex
        while searchEnd > before.startIndex {
            let prev = text.index(before: searchEnd)
            if text[prev].isWhitespace || text[prev] == "." || text[prev] == "!" || text[prev] == "?" {
                searchEnd = prev
            } else {
                break
            }
        }

        let searchRange = text[text.startIndex..<searchEnd]
        if let dotIndex = searchRange.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            var sentenceStart = text.index(after: dotIndex)
            while sentenceStart < text.endIndex && text[sentenceStart].isWhitespace {
                sentenceStart = text.index(after: sentenceStart)
            }
            cursorUTF16 = sentenceStart.utf16Offset(in: text)
        } else {
            cursorUTF16 = 0
        }
        cursorLengthUTF16 = 0
    }

    func resetCursor() {
        cursorUTF16 = 0
        cursorLengthUTF16 = 0
    }

    func setRate(_ multiplier: Float, restartWith text: String? = nil) {
        speedMultiplier = multiplier

        if isPlaying {
            stop()
        }
    }

    func setVoice(_ voiceID: String, restartWith text: String? = nil) {
        selectedVoiceID = voiceID

        if isPlaying {
            stop()
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let absLocation = self.speakingUTF16Offset + characterRange.location
        let absLength = characterRange.length

        let totalUTF16 = self.fullText.utf16.count
        guard absLocation + absLength <= totalUTF16 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cursorUTF16 = absLocation
            self.cursorLengthUTF16 = absLength
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
            self?.isPaused = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
            self?.isPaused = false
        }
    }
}
