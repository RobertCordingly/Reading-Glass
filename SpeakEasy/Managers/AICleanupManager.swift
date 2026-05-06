import Foundation
import FoundationModels
import SwiftUI

// MARK: - LLM Provider Configuration

/// Which backend handles AI summarization and cleanup.
enum LLMProvider: String, CaseIterable, Identifiable {
    case appleIntelligence = "apple"
    case lmStudio = "lmstudio"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .lmStudio: return "LM Studio (Local Endpoint)"
        }
    }
}

/// User-defaults–backed read access for AI provider settings, used outside the SwiftUI
/// AppStorage layer (e.g. inside background tasks). Keys mirror the @AppStorage keys.
enum LLMSettings {
    static let providerKey = "aiProvider"
    static let baseURLKey = "lmStudioBaseURL"
    static let modelKey = "lmStudioModel"
    static let apiKeyKey = "lmStudioAPIKey"
    static let temperatureKey = "lmStudioTemperature"

    static let defaultBaseURL = "http://localhost:1234/v1"
    static let defaultTemperature = 0.2

    static var provider: LLMProvider {
        let raw = UserDefaults.standard.string(forKey: providerKey) ?? LLMProvider.lmStudio.rawValue
        return LLMProvider(rawValue: raw) ?? .lmStudio
    }

    static var lmStudioBaseURL: String {
        let stored = UserDefaults.standard.string(forKey: baseURLKey) ?? defaultBaseURL
        return stored.isEmpty ? defaultBaseURL : stored
    }

    static var lmStudioModel: String {
        UserDefaults.standard.string(forKey: modelKey) ?? ""
    }

    static var lmStudioAPIKey: String {
        UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
    }

    static var lmStudioTemperature: Double {
        let raw = UserDefaults.standard.object(forKey: temperatureKey) as? Double
        return raw ?? defaultTemperature
    }
}

// MARK: - LLM Backend Protocol

/// A unified interface over local LLM providers (Apple Intelligence and LM Studio).
protocol LLMBackend: Sendable {
    /// Verifies the backend is reachable and ready. Throws AICleanupError on failure.
    func checkAvailability() async throws

    /// Sends a single non-streaming request and returns the full response text.
    func respond(instructions: String, userMessage: String) async throws -> String
}

// MARK: - Apple Intelligence Backend

struct AppleIntelligenceBackend: LLMBackend {
    func checkAvailability() async throws {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return
        case .unavailable(.deviceNotEligible):
            throw AICleanupError.deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            throw AICleanupError.appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            throw AICleanupError.modelNotReady
        case .unavailable:
            throw AICleanupError.unavailable
        }
    }

    func respond(instructions: String, userMessage: String) async throws -> String {
        try await checkAvailability()
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = LanguageModelSession(instructions: trimmed.isEmpty ? "Return the text unchanged." : trimmed)
        let response = try await session.respond(to: userMessage)
        return response.content
    }
}

// MARK: - LM Studio Backend (OpenAI-compatible)

struct LMStudioBackend: LLMBackend {
    let baseURL: String
    let model: String
    let apiKey: String
    let temperature: Double

    init(
        baseURL: String = LLMSettings.lmStudioBaseURL,
        model: String = LLMSettings.lmStudioModel,
        apiKey: String = LLMSettings.lmStudioAPIKey,
        temperature: Double = LLMSettings.lmStudioTemperature
    ) {
        self.baseURL = LMStudioBackend.normalize(baseURL)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.temperature = temperature
    }

    /// Strips trailing slashes and obvious endpoint paths a user might paste in.
    private static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        for suffix in ["/chat/completions", "/completions"] {
            if s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
                break
            }
        }
        if s.isEmpty { s = LLMSettings.defaultBaseURL }
        return s
    }

    func checkAvailability() async throws {
        guard let url = URL(string: baseURL + "/models") else {
            throw AICleanupError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AICleanupError.lmStudioUnreachable
            }
            if !(200..<300).contains(http.statusCode) {
                throw AICleanupError.lmStudioBadStatus(http.statusCode)
            }
        } catch let err as AICleanupError {
            throw err
        } catch {
            throw AICleanupError.lmStudioUnreachable
        }
    }

    /// Lists the models currently loaded in LM Studio. Used by the settings sheet to
    /// populate a picker so the user doesn't need to type a model identifier.
    func listModels() async throws -> [String] {
        guard let url = URL(string: baseURL + "/models") else {
            throw AICleanupError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AICleanupError.lmStudioUnreachable
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { $0["id"] as? String }.sorted()
    }

    func respond(instructions: String, userMessage: String) async throws -> String {
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = trimmedInstructions.isEmpty ? "Return the text unchanged." : trimmedInstructions

        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw AICleanupError.invalidEndpoint
        }

        var body: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": temperature,
            "stream": false
        ]
        if !model.isEmpty {
            body["model"] = model
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 300
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AICleanupError.lmStudioUnreachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw AICleanupError.lmStudioUnreachable
        }
        if !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(200) ?? ""
            throw AICleanupError.lmStudioRequestFailed(http.statusCode, String(bodyText))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AICleanupError.lmStudioBadResponse
        }
        return content
    }
}

// MARK: - Backend Factory

enum LLMBackendFactory {
    /// Builds the backend currently selected in user defaults.
    static func current() -> LLMBackend {
        switch LLMSettings.provider {
        case .appleIntelligence: return AppleIntelligenceBackend()
        case .lmStudio: return LMStudioBackend()
        }
    }
}

/// Manages AI cleanup (chunk-based text cleaning) and summarization through a
/// pluggable backend (Apple Intelligence or a local LM Studio endpoint).
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

    /// Summarizes text using the configured backend.
    /// - Returns: The summary string, or throws an `AICleanupError` for UI display.
    func summarize(text: String) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }

        let backend = LLMBackendFactory.current()
        try await backend.checkAvailability()

        let instructions = """
            You are a helpful research assistant. Provide a concise and comprehensive \
            summary of the given text. Capture the main points and convey the author's \
            intended meaning accurately. Do not add any information not in the original \
            text. Keep the summary focused and appropriately brief.
            """
        return try await backend.respond(instructions: instructions, userMessage: text)
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
        let backend = LLMBackendFactory.current()

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
        backgroundCleanStatus = "Connecting..."

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
            do {
                try await backend.checkAvailability()
            } catch {
                let message = (error as? AICleanupError)?.errorDescription ?? error.localizedDescription
                backgroundCleanStatus = message
                backgroundCleanProgress = 0
                isCleaningInBackground = false
                return
            }

            backgroundCleanStatus = "Typos 1/\(indicesToClean.count)..."

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

                let afterTypos = await aiCleanSection(chunkText, prompt: typoFixPrompt, backend: backend)
                if cleanupGeneration != currentGeneration { return }

                // Pass 2: Content cleanup
                backgroundCleanProgress = (Double(step) * 2 + 1) / Double(indicesToClean.count * 2)
                backgroundCleanStatus = "Cleanup \(step + 1)/\(indicesToClean.count)..."

                let afterCleanup = await aiCleanSection(afterTypos, prompt: aiCleanupPrompt, backend: backend)
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

    private func aiCleanSection(_ text: String, prompt: String, backend: LLMBackend) async -> String {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }
        do {
            return try await backend.respond(instructions: prompt, userMessage: text)
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
    // Apple Intelligence
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable

    // LM Studio
    case invalidEndpoint
    case lmStudioUnreachable
    case lmStudioBadStatus(Int)
    case lmStudioRequestFailed(Int, String)
    case lmStudioBadResponse

    var errorDescription: String? {
        switch self {
        case .deviceNotEligible:
            return "Apple Intelligence is not available on this device."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is available but not enabled. Enable it in System Settings."
        case .modelNotReady:
            return "The Apple Intelligence model isn't ready yet. Please try again later."
        case .unavailable:
            return "Apple Intelligence is unavailable."
        case .invalidEndpoint:
            return "The LM Studio endpoint URL is not valid."
        case .lmStudioUnreachable:
            return "Could not reach LM Studio. Make sure it's running and the server is started."
        case .lmStudioBadStatus(let code):
            return "LM Studio returned HTTP \(code) when checking availability."
        case .lmStudioRequestFailed(let code, let body):
            return body.isEmpty ? "LM Studio request failed (HTTP \(code))." : "LM Studio request failed (HTTP \(code)): \(body)"
        case .lmStudioBadResponse:
            return "LM Studio returned an unexpected response format."
        }
    }
}
