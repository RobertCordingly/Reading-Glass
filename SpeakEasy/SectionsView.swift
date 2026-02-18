import SwiftUI

/// A section header found in the processed text, with indentation level.
struct SectionItem: Identifiable {
    let id = UUID()
    let title: String
    let utf16Offset: Int
    let level: Int  // 0 = top-level (roman numeral / numeric), 1 = sub-section (letter / x.y)
}

/// Tree-style list of paper sections for navigation.
struct SectionsView: View {
    let sections: [SectionItem]
    let onSectionSelected: (SectionItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if sections.isEmpty {
                Spacer()
                Text("No sections found")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                Text("Import a PDF to see its structure")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                Spacer()
            } else {
                HStack {
                    Text("\(sections.count) section\(sections.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                List {
                    ForEach(sections) { section in
                        Button {
                            onSectionSelected(section)
                        } label: {
                            HStack(spacing: 6) {
                                if section.level > 0 {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                Text(section.title)
                                    .font(.system(size: section.level == 0 ? 13 : 12,
                                                  weight: section.level == 0 ? .semibold : .regular))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.leading, CGFloat(section.level) * 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                    Color.clear.frame(height: 80)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
