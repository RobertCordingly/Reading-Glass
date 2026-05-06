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
