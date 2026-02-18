import SwiftUI
import AppKit

/// Pronunciation replacements editor sheet.
struct PronunciationEditorView: View {
    @Binding var pronunciations: [PronunciationEntry]
    let onClose: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pronunciation Replacements")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            HStack(spacing: 8) {
                Text("Find")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Speak As")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 28)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 2)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach($pronunciations) { $entry in
                    HStack(spacing: 8) {
                        TextField("Text", text: $entry.find)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        TextField("Spoken as", text: $entry.replace)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        Button(action: {
                            pronunciations.removeAll { $0.id == entry.id }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(action: {
                    pronunciations.append(PronunciationEntry(find: "", replace: ""))
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Replacement")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            HStack {
                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply Now") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
