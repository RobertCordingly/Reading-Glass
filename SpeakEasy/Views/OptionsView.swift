import SwiftUI

/// Options/settings sheet.
struct OptionsView: View {
    @Binding var ignoreBeforeAbstract: Bool
    @Binding var ignoreReferences: Bool
    @Binding var skipCitations: Bool
    @Binding var removeFiguresAndTables: Bool
    @Binding var aiCleanupPrompt: String
    @Binding var replaceParentheses: Bool
    @Binding var speakGreekLetters: Bool
    @Binding var speakMathSymbols: Bool
    @Binding var showEditor: Bool
    let onDone: () -> Void

    @AppStorage(LLMSettings.providerKey) private var aiProviderRaw = LLMProvider.lmStudio.rawValue
    @AppStorage(LLMSettings.baseURLKey) private var lmStudioBaseURL = LLMSettings.defaultBaseURL
    @AppStorage(LLMSettings.modelKey) private var lmStudioModel = ""
    @AppStorage(LLMSettings.apiKeyKey) private var lmStudioAPIKey = ""
    @AppStorage(LLMSettings.temperatureKey) private var lmStudioTemperature = LLMSettings.defaultTemperature

    @AppStorage(CleanupSettings.sentencesPerChunkKey) private var aiSentencesPerChunk = CleanupSettings.defaultSentencesPerChunk
    @AppStorage(CleanupSettings.windowChunksKey) private var aiWindowChunks = CleanupSettings.defaultWindowChunks
    @AppStorage(CleanupSettings.contextSentencesKey) private var aiContextSentences = CleanupSettings.defaultContextSentences
    @AppStorage(CleanupSettings.maxDeviationPercentKey) private var aiMaxDeviationPercent = CleanupSettings.defaultMaxDeviationPercent
    @AppStorage(CleanupSettings.useTwoPassKey) private var aiUseTwoPass = CleanupSettings.defaultUseTwoPass
    @AppStorage(CleanupSettings.cleanWholeDocumentKey) private var aiCleanWholeDocument = CleanupSettings.defaultCleanWholeDocument

    @State private var availableModels: [String] = []
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var isCheckingConnection = false

    private enum ConnectionStatus {
        case idle
        case ok(modelCount: Int)
        case error(String)
    }

    private var aiProvider: LLMProvider {
        LLMProvider(rawValue: aiProviderRaw) ?? .lmStudio
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Options")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                Divider()

                contentSection

                Divider()

                aiProviderSection

                Divider()

                aiCleanupSection

                Divider()

                textProcessingSection

                Divider()

                viewSection
            }
        }
        .frame(maxHeight: 600)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Button("Done") {
                        onDone()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.platformWindowBackground)
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Content")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle(isOn: $ignoreBeforeAbstract) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ignore Before Abstract")
                        .font(.system(size: 13))
                    Text("Remove text before the Abstract section")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $ignoreReferences) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ignore After References")
                        .font(.system(size: 13))
                    Text("Truncate text after the References section")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $skipCitations) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skip Citations")
                        .font(.system(size: 13))
                    Text("Remove inline citation brackets like [1], [2-5]")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var aiProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Provider")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Picker("Backend", selection: $aiProviderRaw) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text(aiProvider == .lmStudio
                 ? "Send AI requests to a local LM Studio server. The model and prompts run entirely on your machine."
                 : "Use Apple Intelligence (the on-device system language model). Requires a supported Mac or iPad.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if aiProvider == .lmStudio {
                lmStudioFields
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var lmStudioFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Server URL")
                    .font(.system(size: 12, weight: .medium))
                TextField("http://localhost:1234/v1", text: $lmStudioBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Text("LM Studio's OpenAI-compatible endpoint. Default port is 1234. Start the server from the LM Studio Developer tab.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Model")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button {
                        Task { await refreshModels() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Fetch the list of currently loaded models from LM Studio")
                }
                if availableModels.isEmpty {
                    TextField("e.g. llama-3.1-8b-instruct (leave blank for default)", text: $lmStudioModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                } else {
                    Picker("", selection: $lmStudioModel) {
                        Text("(use server default)").tag("")
                        ForEach(availableModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                }
                Text("Optional. Leave blank to use whichever model LM Studio has loaded.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.system(size: 12, weight: .medium))
                SecureField("(usually empty for LM Studio)", text: $lmStudioAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(String(format: "%.2f", lmStudioTemperature))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $lmStudioTemperature, in: 0.0...1.0, step: 0.05)
                Text("Lower values give more deterministic, on-task responses (recommended for cleanup).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await testConnection() }
                } label: {
                    if isCheckingConnection {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(isCheckingConnection)

                connectionStatusLabel
            }
            .padding(.top, 4)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }

    @ViewBuilder
    private var connectionStatusLabel: some View {
        switch connectionStatus {
        case .idle:
            EmptyView()
        case .ok(let count):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(count == 0 ? "Connected" : "Connected — \(count) model\(count == 1 ? "" : "s") loaded")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var aiCleanupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Cleanup")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle(isOn: $removeFiguresAndTables) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable AI Cleanup")
                        .font(.system(size: 13))
                    Text("Use the configured AI provider to clean text (strip figures, tables, fix typos, etc.)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            cleanupPipelineControls

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt")
                    .font(.system(size: 13))
                Text("Instructions sent to the AI for each text chunk")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextEditor(text: $aiCleanupPrompt)
                    .font(.system(size: 11))
                    .frame(minHeight: 120, maxHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Per-pipeline knobs: chunk granularity, window, context, acceptance, two-pass.
    @ViewBuilder
    private var cleanupPipelineControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pipeline Behavior")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            stepperRow(
                title: "Sentences per chunk",
                detail: "How many sentences are sent to the LLM in a single request. Larger gives more context per call but uses more tokens.",
                value: $aiSentencesPerChunk,
                range: CleanupSettings.sentencesPerChunkRange
            )

            Toggle(isOn: $aiCleanWholeDocument) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean whole document")
                        .font(.system(size: 13))
                    Text("Off: only ±N chunks around the cursor are cleaned (fast). On: every chunk is cleaned in one run (slow but thorough).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            stepperRow(
                title: "Window (chunks before/after cursor)",
                detail: "How many chunks on each side of the cursor are cleaned per click. Ignored when 'Clean whole document' is on.",
                value: $aiWindowChunks,
                range: CleanupSettings.windowChunksRange,
                disabled: aiCleanWholeDocument
            )

            stepperRow(
                title: "Prior-context sentences",
                detail: "Number of preceding sentences sent as read-only context. Helps the model handle pronouns and references. Set to 0 to disable.",
                value: $aiContextSentences,
                range: CleanupSettings.contextSentencesRange
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Max length deviation")
                        .font(.system(size: 13))
                    Spacer()
                    Text("\(Int(aiMaxDeviationPercent))%")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $aiMaxDeviationPercent, in: CleanupSettings.deviationPercentRange, step: 5)
                Text("Reject the LLM's output if its length differs from the original by more than this. Catches paraphrasing and accidental deletions.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $aiUseTwoPass) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Two-pass cleanup")
                        .font(.system(size: 13))
                    Text("Run a typo-fix pass before the content cleanup pass. Doubles the number of LLM calls. Disable for faster runs with capable models.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }

    private func stepperRow(
        title: String,
        detail: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        disabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper("", value: value, in: range)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(disabled)
            }
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(disabled ? 0.5 : 1.0)
    }

    private var textProcessingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text Processing")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle(isOn: $replaceParentheses) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replace Parentheses")
                        .font(.system(size: 13))
                    Text("Convert parentheses to commas for smoother speech")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $speakGreekLetters) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speak Greek Letters")
                        .font(.system(size: 13))
                    Text("Read Greek symbols aloud (e.g. α as \"alpha\")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $speakMathSymbols) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speak Math Symbols")
                        .font(.system(size: 13))
                    Text("Read math symbols aloud (e.g. ≤ as \"less than or equal to\")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var viewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("View")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle(isOn: $showEditor) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Editor")
                        .font(.system(size: 13))
                    Text("Show the raw text editor tab in the sidebar")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @MainActor
    private func testConnection() async {
        isCheckingConnection = true
        defer { isCheckingConnection = false }
        let backend = LMStudioBackend(
            baseURL: lmStudioBaseURL,
            model: lmStudioModel,
            apiKey: lmStudioAPIKey,
            temperature: lmStudioTemperature
        )
        do {
            try await backend.checkAvailability()
            let models = (try? await backend.listModels()) ?? []
            availableModels = models
            connectionStatus = .ok(modelCount: models.count)
        } catch {
            let message = (error as? AICleanupError)?.errorDescription ?? error.localizedDescription
            connectionStatus = .error(message)
        }
    }

    @MainActor
    private func refreshModels() async {
        let backend = LMStudioBackend(
            baseURL: lmStudioBaseURL,
            model: lmStudioModel,
            apiKey: lmStudioAPIKey,
            temperature: lmStudioTemperature
        )
        do {
            availableModels = try await backend.listModels()
            connectionStatus = .ok(modelCount: availableModels.count)
        } catch {
            let message = (error as? AICleanupError)?.errorDescription ?? error.localizedDescription
            connectionStatus = .error(message)
        }
    }
}
