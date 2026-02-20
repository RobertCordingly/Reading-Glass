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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Options")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            Divider()

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

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("AI Cleanup")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Toggle(isOn: $removeFiguresAndTables) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable AI Cleanup")
                            .font(.system(size: 13))
                        Text("Use Apple Intelligence to clean text (strip figures, tables, fix typos, etc.)")
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

            Divider()

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

            Divider()

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
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
