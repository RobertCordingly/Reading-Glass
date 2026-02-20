import Foundation
import FoundationModels
import SwiftUI

/// Manages AI cleanup (chunk-based text cleaning) and summarization using Apple Intelligence.
@MainActor
final class AICleanupManager: ObservableObject {
    @Published var aiCleanedChunks: [Int: String] = [:]
    @Published var cleanupLog: [CleanupLogEntry] = []
    @Published var isCleaningInBackground = false
    @Published var backgroundCleanProgress: Double = 0
    @Published var backgroundCleanStatus = ""

    private var cleanupGeneration = 0

    private let typoFixPrompt = """
        Fix any spelling errors, typos, or garbage/unreadable characters in this text. \
        Do not remove any content. Return the corrected text exactly as-is otherwise.
        """

    /// Clears all AI cleanup state.
    func clear() {
        aiCleanedChunks = [:]
        cleanupLog = []
    }

    /// Reverts a single cleanup log entry (removes its chunk override and log entry).
    func revert(entry: CleanupLogEntry) {
        aiCleanedChunks.removeValue(forKey: entry.chunkIndex)
        cleanupLog.removeAll { $0.id == entry.id }
    }

    /// Stops any in-progress cleanup.
    func stopCleanup() {
        cleanupGeneration += 1
    }

    /// Summarizes text using Apple Intelligence.
    /// - Returns: The summary string, or throws with an error message for UI display.
    func summarize(text: String) async throws -> String {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            throw AICleanupError.deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            throw AICleanupError.appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            throw AICleanupError.modelNotReady
        case .unavailable:
            throw AICleanupError.unavailable
        }

        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ""
        }

        let instructions = """
            You are a helpful research assistant. Provide a concise and comprehensive \
            summary of the given text. Capture the main points and convey the author's \
            intended meaning accurately. Do not add any information not in the original \
            text. Keep the summary focused and appropriately brief.
            """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text)
        return response.content
    }

    /// Runs chunk-based AI cleanup on chunks around the cursor position.
    /// Each chunk goes through two passes: typo fixing, then content cleanup.
    /// - Parameters:
    ///   - cleanedText: The full text to clean
    ///   - parsedSections: Section headers for changelog labels
    ///   - aiCleanupPrompt: Instructions sent to the AI for each chunk (Pass 2)
    ///   - cursorUTF16: Current cursor position — cleanup focuses on chunks around this offset
    ///   - onDisplayTextUpdate: Called after each chunk is cleaned, with the updated merged text
    func startChunkBasedCleanup(
        cleanedText: String,
        parsedSections: [SectionItem],
        aiCleanupPrompt: String,
        cursorUTF16: Int,
        onDisplayTextUpdate: @escaping (String, [Int]) -> Void
    ) {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return }

        let currentGeneration = cleanupGeneration
        let nsText = cleanedText as NSString
        guard nsText.length > 0 else { return }

        let chunks = Self.makeChunks(from: cleanedText)

        // Find chunk containing cursor and select a window of ±5 chunks
        let cursorChunkIdx = chunks.firstIndex(where: { $0.end > cursorUTF16 }) ?? 0
        let windowStart = max(0, cursorChunkIdx - 5)
        let windowEnd = min(chunks.count, cursorChunkIdx + 6)

        let indicesToClean = (windowStart..<windowEnd)
            .filter { idx in chunks[idx].end - chunks[idx].start >= 20 }

        guard !indicesToClean.isEmpty else { return }

        isCleaningInBackground = true
        backgroundCleanProgress = 0
        backgroundCleanStatus = "Typos 1/\(indicesToClean.count)..."

        let sectionTitlesByChunk: [Int: String] = Dictionary(uniqueKeysWithValues: indicesToClean.map { idx in
            let start = chunks[idx].start
            let title: String
            if parsedSections.isEmpty {
                title = "Chunk \(idx + 1)"
            } else {
                let i = (0..<parsedSections.count).last(where: { parsedSections[$0].utf16Offset <= start }) ?? 0
                title = parsedSections[i].title
            }
            return (idx, title)
        })

        Task {
            for (step, chunkIdx) in indicesToClean.enumerated() {
                if cleanupGeneration != currentGeneration {
                    isCleaningInBackground = false
                    return
                }

                let (start, end) = chunks[chunkIdx]
                let chunkText = nsText.substring(with: NSRange(location: start, length: end - start))
                let sectionTitle = sectionTitlesByChunk[chunkIdx] ?? "Chunk \(chunkIdx + 1)"
                let originalLength = chunkText.count

                // Pass 1: Fix typos
                backgroundCleanProgress = (Double(step) * 2) / Double(indicesToClean.count * 2)
                backgroundCleanStatus = "Typos \(step + 1)/\(indicesToClean.count)..."

                let afterTypos = await aiCleanSection(chunkText, prompt: typoFixPrompt)
                if cleanupGeneration != currentGeneration { return }

                // Pass 2: Content cleanup
                backgroundCleanProgress = (Double(step) * 2 + 1) / Double(indicesToClean.count * 2)
                backgroundCleanStatus = "Cleanup \(step + 1)/\(indicesToClean.count)..."

                let afterCleanup = await aiCleanSection(afterTypos, prompt: aiCleanupPrompt)
                if cleanupGeneration != currentGeneration { return }

                let hasMeaningfulChange = !Self.isWhitespaceOnlyChange(original: chunkText, modified: afterCleanup)
                let finalChunk = hasMeaningfulChange ? afterCleanup : chunkText

                if hasMeaningfulChange {
                    aiCleanedChunks[chunkIdx] = finalChunk
                    cleanupLog.append(CleanupLogEntry(
                        chunkIndex: chunkIdx,
                        sectionTitle: sectionTitle,
                        beforeText: chunkText,
                        afterText: finalChunk,
                        originalLength: originalLength,
                        cleanedLength: finalChunk.count
                    ))
                    let (displayText, offsets) = Self.buildDisplayTextFromChunks(
                        cleanedText: cleanedText,
                        aiCleanedChunks: aiCleanedChunks,
                        chunks: chunks,
                        parsedSections: parsedSections
                    )
                    onDisplayTextUpdate(displayText, offsets)
                }
            }

            backgroundCleanProgress = 1.0
            backgroundCleanStatus = ""
            isCleaningInBackground = false
        }
    }

    private func aiCleanSection(_ text: String, prompt: String) async -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return text }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }

        do {
            let instructions = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let session = LanguageModelSession(instructions: instructions.isEmpty ? "Return the text unchanged." : instructions)
            let response = try await session.respond(to: text)
            return response.content
        } catch {
            return text
        }
    }

    // MARK: - Static helpers

    /// Splits text into one chunk per sentence.
    static func makeChunks(from text: String) -> [(start: Int, end: Int)] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var chunks: [(Int, Int)] = []
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: .bySentences
        ) { _, substringRange, _, _ in
            chunks.append((substringRange.location, substringRange.location + substringRange.length))
        }

        if chunks.isEmpty {
            return [(0, nsText.length)]
        }
        return chunks
    }

    static func isWhitespaceOnlyChange(original: String, modified: String) -> Bool {
        let norm = { (s: String) in s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ") }
        return norm(original) == norm(modified)
    }

    /// Builds display text from cleanedText and AI-cleaned chunk overrides. Returns (displayText, sectionOffsets).
    static func buildDisplayTextFromChunks(
        cleanedText: String,
        aiCleanedChunks: [Int: String],
        chunks: [(start: Int, end: Int)],
        parsedSections: [SectionItem]
    ) -> (String, [Int]) {
        let nsText = cleanedText as NSString
        guard nsText.length > 0 else { return ("", []) }

        if aiCleanedChunks.isEmpty {
            let offsets = parsedSections.isEmpty ? [0, nsText.length] : parsedSections.map { $0.utf16Offset } + [nsText.length]
            return (cleanedText, offsets)
        }

        var result = ""
        for (idx, (start, end)) in chunks.enumerated() {
            let original = nsText.substring(with: NSRange(location: start, length: end - start))
            result += aiCleanedChunks[idx] ?? original
        }

        var offsets: [Int]
        if parsedSections.isEmpty {
            offsets = [0, (result as NSString).length]
        } else {
            var outPos = 0
            var sectionIdx = 0
            offsets = [0]
            for (idx, (start, end)) in chunks.enumerated() {
                let content = aiCleanedChunks[idx] ?? nsText.substring(with: NSRange(location: start, length: end - start))
                let len = (content as NSString).length
                while sectionIdx < parsedSections.count {
                    let s = parsedSections[sectionIdx].utf16Offset
                    if start <= s && s < end {
                        offsets.append(outPos)
                        sectionIdx += 1
                    } else {
                        break
                    }
                }
                outPos += len
            }
            while offsets.count < parsedSections.count + 1 {
                offsets.append(outPos)
            }
        }
        return (result, offsets)
    }
}

enum AICleanupError: LocalizedError {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable

    var errorDescription: String? {
        switch self {
        case .deviceNotEligible: return "Apple Intelligence is not available on this device."
        case .appleIntelligenceNotEnabled: return "Apple Intelligence is available but not enabled. Enable it in System Settings."
        case .modelNotReady: return "The language model isn't ready yet. Please try again later."
        case .unavailable: return "Apple Intelligence is unavailable."
        }
    }
}
