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

/// AppStorage keys and defaults for the AI cleanup pipeline behaviour.
/// These live separately from `LLMSettings` because they describe *how* cleanup is
/// performed (chunking, windowing, acceptance) rather than *which* model answers.
enum CleanupSettings {
    static let sentencesPerChunkKey = "cleanupSentencesPerChunk"
    static let windowChunksKey = "cleanupWindowChunks"
    static let contextSentencesKey = "cleanupContextSentences"
    static let maxDeviationPercentKey = "cleanupMaxDeviationPercent"
    static let cleanWholeDocumentKey = "cleanupWholeDocument"

    static let defaultSentencesPerChunk = 4
    static let defaultWindowChunks = 3
    static let defaultContextSentences = 2
    static let defaultMaxDeviationPercent = 50.0
    static let defaultCleanWholeDocument = false

    static let sentencesPerChunkRange = 1...20
    static let windowChunksRange = 1...50
    static let contextSentencesRange = 0...20
    static let deviationPercentRange = 10.0...300.0
}

/// A snapshot of the cleanup pipeline configuration captured at the moment the user
/// presses **AI Cleanup**. Passed by value into the manager so a long‑running cleanup
/// is not affected by the user editing settings mid‑run.
struct AICleanupConfig {
    var sentencesPerChunk: Int = CleanupSettings.defaultSentencesPerChunk
    var windowChunks: Int = CleanupSettings.defaultWindowChunks
    var contextSentences: Int = CleanupSettings.defaultContextSentences
    var maxDeviationPercent: Double = CleanupSettings.defaultMaxDeviationPercent
    var cleanWholeDocument: Bool = CleanupSettings.defaultCleanWholeDocument
}

// MARK: - LLM Backend Protocol

/// A unified interface over local LLM providers (Apple Intelligence and LM Studio).
protocol LLMBackend: Sendable {
    /// Verifies the backend is reachable and ready. Throws AICleanupError on failure.
    func checkAvailability() async throws

    /// Sends a single non-streaming request and returns the full response text.
    func respond(instructions: String, userMessage: String) async throws -> String

    /// Sends a request along with optional read-only context blocks framing the
    /// text to clean. The default implementation embeds the context inline using
    /// XML-style markers; backends are free to override with a more structured
    /// representation (e.g. separate user messages in OpenAI chat format).
    func respond(
        instructions: String,
        priorContext: String?,
        followingContext: String?,
        userMessage: String
    ) async throws -> String
}

extension LLMBackend {
    func respond(
        instructions: String,
        priorContext: String?,
        followingContext: String?,
        userMessage: String
    ) async throws -> String {
        let prior = priorContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        let following = followingContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPrior = !(prior?.isEmpty ?? true)
        let hasFollowing = !(following?.isEmpty ?? true)

        guard hasPrior || hasFollowing else {
            return try await respond(instructions: instructions, userMessage: userMessage)
        }

        let augmentedInstructions = """
            \(instructions.trimmingCharacters(in: .whitespacesAndNewlines))

            The user message contains XML-tagged sections:
              <PRIOR_CONTEXT>…</PRIOR_CONTEXT> is the text immediately before the target. Reference only.
              <FOLLOWING_CONTEXT>…</FOLLOWING_CONTEXT> is the text immediately after the target. Reference only.
              <CLEAN_THIS>…</CLEAN_THIS> is the only text you should clean and return.
            Do NOT include any text from the context sections in your reply.
            Return only the cleaned contents of <CLEAN_THIS>, with no XML tags, no preamble, and no extra commentary.
            """

        var augmentedUser = ""
        if let prior, hasPrior {
            augmentedUser += "<PRIOR_CONTEXT>\n\(prior)\n</PRIOR_CONTEXT>\n\n"
        }
        augmentedUser += "<CLEAN_THIS>\n\(userMessage)\n</CLEAN_THIS>"
        if let following, hasFollowing {
            augmentedUser += "\n\n<FOLLOWING_CONTEXT>\n\(following)\n</FOLLOWING_CONTEXT>"
        }

        return try await respond(instructions: augmentedInstructions, userMessage: augmentedUser)
    }
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
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            throw CancellationError()
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
        try await respondInternal(messages: [
            ["role": "system", "content": systemPrompt(from: instructions)],
            ["role": "user", "content": userMessage]
        ])
    }

    /// Override to send each context block as its own user message — gives
    /// well‑instructed chat models a cleaner separation than inline XML markers.
    func respond(
        instructions: String,
        priorContext: String?,
        followingContext: String?,
        userMessage: String
    ) async throws -> String {
        let prior = priorContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        let following = followingContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPrior = !(prior?.isEmpty ?? true)
        let hasFollowing = !(following?.isEmpty ?? true)

        guard hasPrior || hasFollowing else {
            return try await respond(instructions: instructions, userMessage: userMessage)
        }

        let system = """
            \(systemPrompt(from: instructions))

            You will receive context messages (PRIOR CONTEXT and/or FOLLOWING CONTEXT) for \
            reference only — do NOT include any of their content in your output. The final \
            user message is the TEXT TO CLEAN. Reply only with the cleaned version of the \
            TEXT TO CLEAN, with no preamble.
            """

        var messages: [[String: String]] = [["role": "system", "content": system]]
        if let prior, hasPrior {
            messages.append(["role": "user", "content": "PRIOR CONTEXT (do not reproduce):\n\(prior)"])
            messages.append(["role": "assistant", "content": "Understood."])
        }
        if let following, hasFollowing {
            messages.append(["role": "user", "content": "FOLLOWING CONTEXT (do not reproduce):\n\(following)"])
            messages.append(["role": "assistant", "content": "Understood. Send the text to clean."])
        }
        messages.append(["role": "user", "content": "TEXT TO CLEAN:\n\(userMessage)"])

        return try await respondInternal(messages: messages)
    }

    private func systemPrompt(from instructions: String) -> String {
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Return the text unchanged." : trimmed
    }

    private func respondInternal(messages: [[String: String]]) async throws -> String {
        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw AICleanupError.invalidEndpoint
        }

        var body: [String: Any] = [
            "messages": messages,
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
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            throw CancellationError()
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

    /// UTF-16 range, in `displayText` coordinates, of the chunk currently being
    /// processed by the LLM. `nil` when no chunk is in flight. The reader view uses
    /// this to draw a soft highlight so the user can see what cleanup is touching.
    @Published var cleaningRangeInDisplay: NSRange? = nil

    /// UTF-16 range, in `displayText` coordinates, covering the chunk currently in
    /// flight *plus* the surrounding context sentences sent to the LLM. The reader
    /// view draws this with a more subtle yellow so the user can see how much
    /// surrounding text the model is reading for context.
    @Published var cleaningContextRangeInDisplay: NSRange? = nil

    private var cleanupTask: Task<Void, Never>?

    /// Clears all AI cleanup state.
    func clear() {
        aiCleanedChunks = [:]
        cleanupLog = []
        cleaningRangeInDisplay = nil
        cleaningContextRangeInDisplay = nil
    }

    /// Reverts a single cleanup log entry (removes its chunk override and log entry).
    func revert(entry: CleanupLogEntry) {
        aiCleanedChunks.removeValue(forKey: entry.chunkIndex)
        cleanupLog.removeAll { $0.id == entry.id }
    }

    /// Stops any in-progress cleanup. Cancels both the loop *and* the in-flight
    /// LLM request so the user doesn't have to wait for the current chunk to return.
    func stopCleanup() {
        cleanupTask?.cancel()
        cleanupTask = nil
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

    /// Runs chunk-based AI cleanup. Sentences are grouped into chunks of
    /// `config.sentencesPerChunk`. By default cleanup walks a window of
    /// ±`config.windowChunks` chunks around the cursor, but `cleanWholeDocument` runs
    /// the full document. Each chunk gets a single LLM call using the user's prompt,
    /// seeded with the surrounding sentences as read‑only context.
    func startChunkBasedCleanup(
        cleanedText: String,
        parsedSections: [SectionItem],
        aiCleanupPrompt: String,
        cursorUTF16: Int,
        config: AICleanupConfig,
        onDisplayTextUpdate: @escaping (String, [Int]) -> Void
    ) {
        let backend = LLMBackendFactory.current()

        let nsText = cleanedText as NSString
        guard nsText.length > 0 else { return }

        let sentencesPerChunk = max(1, config.sentencesPerChunk)
        let windowChunks = max(0, config.windowChunks)
        let contextSentences = max(0, config.contextSentences)
        let maxDeviationPercent = max(0, config.maxDeviationPercent)

        let sentenceRanges = Self.makeSentenceRanges(from: cleanedText)
        let chunks = Self.groupSentences(sentenceRanges, perChunk: sentencesPerChunk)
        guard !chunks.isEmpty else { return }

        // Find chunk containing cursor
        let cursorChunkIdx = chunks.firstIndex(where: { $0.end > cursorUTF16 }) ?? 0

        let candidateRange: Range<Int>
        if config.cleanWholeDocument {
            candidateRange = 0..<chunks.count
        } else {
            let windowStart = max(0, cursorChunkIdx - windowChunks)
            let windowEnd = min(chunks.count, cursorChunkIdx + windowChunks + 1)
            candidateRange = windowStart..<windowEnd
        }

        // Filter out chunks that are too short to be worth cleaning, and chunks that
        // already have an override (no point re‑cleaning what the user kept).
        let indicesToClean = candidateRange.filter { idx in
            chunks[idx].end - chunks[idx].start >= 20 && aiCleanedChunks[idx] == nil
        }

        guard !indicesToClean.isEmpty else { return }

        // Cancel any in-flight cleanup before starting a new one.
        cleanupTask?.cancel()

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

        let totalChunks = indicesToClean.count

        cleanupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await backend.checkAvailability()
            } catch is CancellationError {
                self.isCleaningInBackground = false
                return
            } catch {
                let message = (error as? AICleanupError)?.errorDescription ?? error.localizedDescription
                self.backgroundCleanStatus = message
                self.backgroundCleanProgress = 0
                self.isCleaningInBackground = false
                return
            }

            do {
                for (step, chunkIdx) in indicesToClean.enumerated() {
                    try Task.checkCancellation()

                    let (start, end) = chunks[chunkIdx]
                    let chunkText = nsText.substring(with: NSRange(location: start, length: end - start))
                    let sectionTitle = sectionTitlesByChunk[chunkIdx] ?? "Chunk \(chunkIdx + 1)"
                    let originalLength = chunkText.count

                    // Tell the reader view which range it's currently watching the
                    // model rewrite. Computed against the *current* override state so
                    // it lines up with what's on screen.
                    self.cleaningRangeInDisplay = Self.displayRange(
                        forChunk: chunkIdx,
                        chunks: chunks,
                        aiCleanedChunks: self.aiCleanedChunks
                    )
                    self.cleaningContextRangeInDisplay = Self.contextDisplayRange(
                        forChunk: chunkIdx,
                        chunks: chunks,
                        sentencesPerChunk: sentencesPerChunk,
                        contextSentences: contextSentences,
                        sentenceCount: sentenceRanges.count,
                        aiCleanedChunks: self.aiCleanedChunks
                    )

                    // Build context = N sentences immediately preceding and following this chunk.
                    let (priorContext, followingContext) = Self.buildSurroundingContext(
                        for: chunkIdx,
                        sentenceRanges: sentenceRanges,
                        sentencesPerChunk: sentencesPerChunk,
                        contextSentences: contextSentences,
                        in: nsText
                    )

                    self.backgroundCleanProgress = Double(step) / Double(totalChunks)
                    self.backgroundCleanStatus = "Cleanup \(step + 1)/\(totalChunks)..."

                    let afterCleanup = try await Self.aiCleanSection(
                        chunkText,
                        prompt: aiCleanupPrompt,
                        priorContext: priorContext,
                        followingContext: followingContext,
                        backend: backend
                    )
                    try Task.checkCancellation()

                    let accept = Self.shouldAccept(
                        original: chunkText,
                        modified: afterCleanup,
                        maxDeviationPercent: maxDeviationPercent
                    )

                    // Clear the highlight before mutating overrides — once the override
                    // is applied the chunk's display range shifts (different length),
                    // so the previously published range would point at stale text.
                    self.cleaningRangeInDisplay = nil
                    self.cleaningContextRangeInDisplay = nil

                    if accept {
                        self.aiCleanedChunks[chunkIdx] = afterCleanup
                        self.cleanupLog.append(CleanupLogEntry(
                            chunkIndex: chunkIdx,
                            sectionTitle: sectionTitle,
                            beforeText: chunkText,
                            afterText: afterCleanup,
                            originalLength: originalLength,
                            cleanedLength: afterCleanup.count
                        ))
                        let (displayText, offsets) = Self.buildDisplayTextFromChunks(
                            cleanedText: cleanedText,
                            aiCleanedChunks: self.aiCleanedChunks,
                            chunks: chunks,
                            parsedSections: parsedSections
                        )
                        onDisplayTextUpdate(displayText, offsets)
                    }
                }

                self.cleaningRangeInDisplay = nil
                self.cleaningContextRangeInDisplay = nil
                self.backgroundCleanProgress = 1.0
                self.backgroundCleanStatus = ""
                self.isCleaningInBackground = false
                self.cleanupTask = nil
            } catch is CancellationError {
                self.cleaningRangeInDisplay = nil
                self.cleaningContextRangeInDisplay = nil
                self.backgroundCleanStatus = "Cancelled"
                self.isCleaningInBackground = false
                self.cleanupTask = nil
            } catch {
                self.cleaningRangeInDisplay = nil
                self.cleaningContextRangeInDisplay = nil
                self.backgroundCleanStatus = (error as? AICleanupError)?.errorDescription ?? error.localizedDescription
                self.isCleaningInBackground = false
                self.cleanupTask = nil
            }
        }
    }

    private static func aiCleanSection(
        _ text: String,
        prompt: String,
        priorContext: String?,
        followingContext: String?,
        backend: LLMBackend
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }
        do {
            let result = try await backend.respond(
                instructions: prompt,
                priorContext: priorContext,
                followingContext: followingContext,
                userMessage: text
            )
            // The backend may swallow a cancellation as a generic error; double-check.
            try Task.checkCancellation()
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            throw CancellationError()
        } catch {
            // Non-cancellation failure: fall back to the original text so cleanup
            // continues for the rest of the window instead of aborting wholesale.
            return text
        }
    }

    /// Builds context strings from up to `contextSentences` sentences immediately
    /// preceding *and* immediately following the chunk at `chunkIdx`. Either side
    /// may be nil when no context is requested or available (e.g. at document edges).
    private static func buildSurroundingContext(
        for chunkIdx: Int,
        sentenceRanges: [(start: Int, end: Int)],
        sentencesPerChunk: Int,
        contextSentences: Int,
        in nsText: NSString
    ) -> (prior: String?, following: String?) {
        guard contextSentences > 0 else { return (nil, nil) }
        // Chunks are formed by uniformly grouping `sentencesPerChunk` sentences,
        // starting at sentence 0. So the first sentence of chunk N is at index
        // N * sentencesPerChunk.
        let firstSentenceIdx = chunkIdx * sentencesPerChunk
        let lastSentenceIdx = min(sentenceRanges.count - 1, firstSentenceIdx + sentencesPerChunk - 1)

        let prior = substring(
            sentenceRanges: sentenceRanges,
            startSentence: max(0, firstSentenceIdx - contextSentences),
            endSentenceExclusive: firstSentenceIdx,
            in: nsText
        )

        let followingStart = lastSentenceIdx + 1
        let following = substring(
            sentenceRanges: sentenceRanges,
            startSentence: followingStart,
            endSentenceExclusive: min(sentenceRanges.count, followingStart + contextSentences),
            in: nsText
        )

        return (prior, following)
    }

    /// Substring helper: joins the text spanned by `[startSentence, endSentenceExclusive)`
    /// into a single trimmed string, or nil if the range is empty.
    private static func substring(
        sentenceRanges: [(start: Int, end: Int)],
        startSentence: Int,
        endSentenceExclusive: Int,
        in nsText: NSString
    ) -> String? {
        guard startSentence < endSentenceExclusive,
              startSentence >= 0,
              endSentenceExclusive <= sentenceRanges.count else { return nil }
        let startUTF16 = sentenceRanges[startSentence].start
        let endUTF16 = sentenceRanges[endSentenceExclusive - 1].end
        let length = endUTF16 - startUTF16
        guard length > 0, startUTF16 + length <= nsText.length else { return nil }
        let s = nsText.substring(with: NSRange(location: startUTF16, length: length))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    // MARK: - Static helpers

    /// Splits text into one range per sentence using Foundation's sentence tokenizer.
    static func makeSentenceRanges(from text: String) -> [(start: Int, end: Int)] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var ranges: [(Int, Int)] = []
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: .bySentences
        ) { _, substringRange, _, _ in
            ranges.append((substringRange.location, substringRange.location + substringRange.length))
        }

        if ranges.isEmpty {
            return [(0, nsText.length)]
        }
        return ranges
    }

    /// Groups sentence ranges into chunks of `perChunk` sentences each. The final
    /// chunk may be shorter. The returned ranges are still contiguous and dense, so
    /// concatenating their text reproduces the original input.
    static func groupSentences(
        _ sentenceRanges: [(start: Int, end: Int)],
        perChunk: Int
    ) -> [(start: Int, end: Int)] {
        guard !sentenceRanges.isEmpty else { return [] }
        let n = max(1, perChunk)
        if n == 1 { return sentenceRanges }

        var chunks: [(Int, Int)] = []
        var i = 0
        while i < sentenceRanges.count {
            let groupEnd = min(i + n, sentenceRanges.count)
            let start = sentenceRanges[i].start
            let end = sentenceRanges[groupEnd - 1].end
            chunks.append((start, end))
            i = groupEnd
        }
        return chunks
    }

    /// Top-level chunking entry point. Sentence-grouped if `sentencesPerChunk > 1`.
    static func makeChunks(from text: String, sentencesPerChunk: Int = 1) -> [(start: Int, end: Int)] {
        let sentences = makeSentenceRanges(from: text)
        return groupSentences(sentences, perChunk: sentencesPerChunk)
    }

    static func isWhitespaceOnlyChange(original: String, modified: String) -> Bool {
        let norm = { (s: String) in s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ") }
        return norm(original) == norm(modified)
    }

    /// Whether the LLM's reply should replace the original chunk. Rejects:
    ///  - whitespace-only changes (no new information),
    ///  - empty replies (the model returned nothing),
    ///  - replies whose length deviates by more than `maxDeviationPercent` from the
    ///    original (catches paraphrasing, hallucinated additions, accidental deletion).
    static func shouldAccept(original: String, modified: String, maxDeviationPercent: Double) -> Bool {
        guard !modified.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if isWhitespaceOnlyChange(original: original, modified: modified) { return false }

        let origLen = max(1, original.count)
        let modLen = modified.count
        let deviation = abs(Double(modLen - origLen)) / Double(origLen) * 100.0
        return deviation <= maxDeviationPercent
    }

    /// Returns the UTF-16 range, in `displayText` coordinates, occupied by the chunk
    /// at `chunkIdx`, using whatever overrides exist in `aiCleanedChunks` for chunks
    /// that come *before* it. The chunk at `chunkIdx` itself is treated as
    /// not-yet-overridden (its length is the original chunk length), which is the
    /// correct invariant during cleanup — the override is applied only after the
    /// LLM call finishes.
    static func displayRange(
        forChunk chunkIdx: Int,
        chunks: [(start: Int, end: Int)],
        aiCleanedChunks: [Int: String]
    ) -> NSRange {
        guard chunkIdx >= 0, chunkIdx < chunks.count else {
            return NSRange(location: 0, length: 0)
        }
        var pos = 0
        for i in 0..<chunkIdx {
            if let override = aiCleanedChunks[i] {
                pos += (override as NSString).length
            } else {
                pos += chunks[i].end - chunks[i].start
            }
        }
        // For chunks where there's already an override (e.g. the user re-runs cleanup
        // and the chunk somehow re-enters the loop), still highlight the overridden
        // span — that's what's on screen.
        let length: Int
        if let override = aiCleanedChunks[chunkIdx] {
            length = (override as NSString).length
        } else {
            length = chunks[chunkIdx].end - chunks[chunkIdx].start
        }
        return NSRange(location: pos, length: length)
    }

    /// Returns the UTF-16 range, in `displayText` coordinates, covering the chunk
    /// at `chunkIdx` *plus* the adjacent chunks that hold its surrounding context
    /// sentences. The reader view draws this with a subtler highlight to show how
    /// much surrounding text the LLM is reading for context. Falls back to the
    /// chunk-only range when no context is configured.
    static func contextDisplayRange(
        forChunk chunkIdx: Int,
        chunks: [(start: Int, end: Int)],
        sentencesPerChunk: Int,
        contextSentences: Int,
        sentenceCount: Int,
        aiCleanedChunks: [Int: String]
    ) -> NSRange {
        guard !chunks.isEmpty, chunkIdx >= 0, chunkIdx < chunks.count else {
            return NSRange(location: 0, length: 0)
        }
        guard contextSentences > 0, sentencesPerChunk > 0, sentenceCount > 0 else {
            return displayRange(forChunk: chunkIdx, chunks: chunks, aiCleanedChunks: aiCleanedChunks)
        }

        let firstSentenceIdx = chunkIdx * sentencesPerChunk
        let lastSentenceIdx = min(sentenceCount - 1, firstSentenceIdx + sentencesPerChunk - 1)
        let priorStartSentence = max(0, firstSentenceIdx - contextSentences)
        let followingEndSentence = min(sentenceCount - 1, lastSentenceIdx + contextSentences)

        let leftChunk = max(0, min(chunks.count - 1, priorStartSentence / sentencesPerChunk))
        let rightChunk = max(0, min(chunks.count - 1, followingEndSentence / sentencesPerChunk))

        var pos = 0
        var startPos = 0
        var endPos = 0
        for i in 0..<chunks.count {
            let len = (aiCleanedChunks[i].map { ($0 as NSString).length }) ?? (chunks[i].end - chunks[i].start)
            if i == leftChunk { startPos = pos }
            pos += len
            if i == rightChunk { endPos = pos; break }
        }
        return NSRange(location: startPos, length: max(0, endPos - startPos))
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
